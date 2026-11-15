# Design

## Context

`Courier.Access` (archived change `add-access-keys`) provides API keys, the `Authenticate`/`RequireScope` plugs, `CourierWeb.FallbackController` and the error shape. This change adds the first domain data. Accepted ADRs that apply: "Event-type filters per endpoint", "Encrypt endpoint secrets at rest" (Cloak.Ecto), "Sign webhooks with the Standard Webhooks scheme" (secret format), "Oban with one queue per endpoint" (the `max_concurrency` setting). Requirements are in `specs/merchants/spec.md` and `specs/webhook-endpoints/spec.md`.

## Goals / Non-Goals

**Goals:**
- Contexts `Courier.Merchants` and `Courier.Endpoints` that ingestion, delivery, the dashboard and MCP will call.
- A URL policy and an event filter that are pure and reusable (delivery re-checks URLs; ingestion matches patterns).
- A cursor pagination helper reused by every later list endpoint.

**Non-Goals:**
- Starting or stopping per-endpoint Oban queues, `consecutive_failures` and `degraded_at` (delivery change).
- Re-checking the URL right before each request (delivery change; it reuses the policy).
- What a disabled merchant means for ingestion (ingestion change).
- Deleting merchants or endpoints.

## Decisions

### Tables

- `merchants`: `id` (binary id), `name` (string, not null), `enabled` (boolean, default true), timestamps (`utc_datetime_usec`). Index on `inserted_at, id` for pagination.
- `endpoints`: `id`, `merchant_id` (references merchants, not null, `on_delete: :restrict`), `url` (text), `description` (text, nullable), `event_types` (array of strings, default `{}`), `enabled` (default true), `retry_window_seconds` (integer, default 86400), `retry_on_4xx` (boolean, default false), `max_concurrency` (integer, default 10), `secret` (binary, encrypted, not null), `previous_secret` (binary, encrypted, nullable), `previous_secret_expires_at` (utc_datetime_usec, nullable), timestamps. Indexes on `merchant_id` and `inserted_at, id`. Check constraints back the numeric ranges.

### Encryption (`Courier.Vault`)

`Courier.Vault` uses `Cloak.Vault` with `Cloak.Ciphers.AES.GCM` (tag `"AES.GCM.V1"`). `Courier.Encrypted.Binary` (`Cloak.Ecto.Binary`) is the field type for `secret` and `previous_secret`. Keys:

- `config/runtime.exs`, prod: `COURIER_ENCRYPTION_KEY` (base64 of 32 bytes) is required; boot fails with a clear message if it is missing or the wrong size.
- `config/dev.exs` and `config/test.exs`: fixed, non-secret keys written in the config files (documented as such).

The vault is a child of `Courier.Application`, started before the repo users. Alternative (pgcrypto in SQL) rejected by the ADR.

### Secrets

`"whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))` (standard base64 with padding, as Standard Webhooks expects). Secrets are set programmatically, never cast from params, and the schema derives `Inspect` without `secret` and `previous_secret`. JSON views never include them; only the create and rotate responses add a `secret` field explicitly.

Rotation: `previous_secret = secret`, `secret = new`, `previous_secret_expires_at = now + 24 h`. `Courier.Endpoints.signing_secrets(endpoint, now \\ DateTime.utc_now())` returns `[secret]` or `[secret, previous_secret]` while `now < previous_secret_expires_at`. The overlap is a module attribute (24 h) so tests can pass `now`.

### URL policy (`Courier.Endpoints.URLPolicy`)

`check(url, opts \\ []) :: :ok | {:error, reason}` with options defaulting to app config (`config :courier, Courier.Endpoints.URLPolicy, require_https: true, allowed_hosts: [], resolver: Courier.Endpoints.DNSResolver`):

1. Parse with `URI.new/1`; require scheme `https` (or `http` when `require_https: false`), a non-empty host, no `userinfo`.
2. If the host (case-insensitive) is in `allowed_hosts`, accept.
3. If the host is an IP literal (`:inet.parse_address/1`, brackets stripped for IPv6), check it; otherwise resolve it with the resolver (`resolve(host) :: {:ok, [:inet.ip_address()]} | {:error, term}`), which by default merges `:inet.getaddrs/2` for `:inet` and `:inet6`. No addresses → reject.
4. Every resolved address must be public. Blocked IPv4: `0.0.0.0/8`, `10.0.0.0/8`, `100.64.0.0/10`, `127.0.0.0/8`, `169.254.0.0/16`, `172.16.0.0/12`, `192.0.0.0/24`, `192.168.0.0/16`, `198.18.0.0/15`, `224.0.0.0/4`, `240.0.0.0/4` (includes broadcast). Blocked IPv6: `::/96` (unspecified, loopback and the deprecated IPv4-compatible addresses such as `::127.0.0.1`), `fc00::/7`, `fe80::/10`, `ff00::/8`; IPv4-mapped (`::ffff:0:0/96`) and NAT64 (`64:ff9b::/96`) addresses are checked as their embedded IPv4.

The changeset turns any error into a single message on `url` ("must be a public https URL") without echoing resolved addresses.

Config: dev `require_https: false, allowed_hosts: ["localhost", "127.0.0.1", "demo-receiver"]`; test `require_https: true, allowed_hosts: [], resolver: Courier.Endpoints.TestResolver`; prod uses the defaults (the Docker demo will set its allowlist in the demo change).

`Courier.Endpoints.TestResolver` lives in a new file `test/support/test_resolver.ex` and resolves by convention, so async tests need no shared state: `*.public.test` → `93.184.216.34`, `*.private.test` → `10.0.0.5`, `*.v6private.test` → `fd00::1`, anything else → `{:error, :nxdomain}`. Tests use hosts such as `hooks.public.test`.

Alternative: validate only at delivery time. Rejected: operators should learn about a bad URL when they save it; delivery re-checks anyway because DNS can change.

### Event filter (`Courier.Endpoints.EventFilter`)

- `valid_pattern?/1` with `~r/\A[a-z0-9_]+(\.[a-z0-9_]+)*(\.\*)?\z/` (so `*` alone, uppercase, inner wildcards and empty strings fail).
- `matches?(patterns, type)`: `[]` → true; exact equality; `"prefix.*"` matches when `type` starts with `"prefix."`.
- The changeset de-duplicates patterns and limits the list to 50 entries.

### Pagination (`Courier.Pagination`)

`paginate(query, %{limit: n, cursor: c | nil}) :: {:ok, %{items: [...], next_cursor: String.t() | nil}} | {:error, :invalid_cursor}` using keyset pagination on `(inserted_at, id)` ascending; fetches `limit + 1` rows to know whether there is a next page. The cursor is `Base.url_encode64` of `"<inserted_at ISO 8601 usec>|<id>"`; a cursor that fails to decode or parse is `{:error, :invalid_cursor}`. `CourierWeb.Params.pagination(params)` parses `limit` (default 50, 1..100) and `cursor`, returning `{:error, :invalid_pagination}` for bad values; the fallback controller maps both errors to `422 invalid`.

### Web layer

- `MerchantController` (`index`, `show`, `create`, `update`) and `EndpointController` (`index`, `show`, `create`, `update`, `rotate_secret`), both with `action_fallback CourierWeb.FallbackController` and `plug RequireScope, :read when action in [:index, :show]` / `plug RequireScope, :write when action in [...]`.
- Routes under the existing `scope "/api/v1"`: `resources "/merchants", MerchantController, only: [:index, :show, :create, :update]`, the same for endpoints, and `post "/endpoints/:id/rotate_secret"`.
- Unknown or malformed ids return `{:error, :not_found}` (ids are parsed with `Ecto.UUID.cast/1` before querying). An unknown `merchant_id` when creating an endpoint is a changeset error (`foreign_key_constraint` plus an existence check), so it is `422`.
- JSON: `MerchantJSON` and `EndpointJSON` render ids, fields and ISO 8601 timestamps; list responses are `{"data": [...], "next_cursor": ...}`, single resources `{"data": {...}}`.

### Quieter Mix tasks

Each `mix courier.keys.*` task raises its own process's log level to at least `:info` before `app.start` (`Logger.put_process_level/2`, never lowering a stricter global level), so Ecto's debug SQL lines disappear without changing logging for the rest of the system or the test suite.

## Risks / Trade-offs

- [DNS rebinding: a host resolves to a public address at save time and a private one later] → The delivery change re-checks before each request and pins the resolved address; this change only validates at save time.
- [DNS lookups make endpoint creation slower and depend on the network] → One lookup per create or URL change; tests never hit the network thanks to the test resolver.
- [Losing `COURIER_ENCRYPTION_KEY` makes stored secrets unreadable] → Documented; operators rotate endpoint secrets after restoring a key. Cloak supports key rotation later.
- [Keyset cursors expose creation times when decoded] → Acceptable: they are not secret and only reach authenticated callers.

## Migration Plan

Two additive migrations (`merchants`, then `endpoints`). Rollback drops them in reverse order. Production needs `COURIER_ENCRYPTION_KEY` before deploying.
