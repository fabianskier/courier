# Design

## Context

The app is a fresh Phoenix 1.8 JSON app (`--no-html`, `--binary-id`) with an empty `/api` scope and Oban. The accepted ADR "API keys with scopes" fixes the model: random tokens stored as SHA-256 hashes, scopes `ingest`, `read`, `write`, created by a Mix task. Later changes reuse this for ingestion (`ingest`), the dashboard and its channel (`read`/`write`) and MCP (`read`/`write`). Requirements are in `specs/api-access/spec.md`.

## Goals / Non-Goals

**Goals:**
- One `Courier.Access` context that every adapter (controllers, the future channel and MCP) calls to authenticate a token and check a scope.
- A plug pair that later changes reuse by declaring a scope per route.
- The API error shape every later controller uses.

**Non-Goals:**
- Key expiry, rotation, `last_used_at` tracking, rate limiting.
- An HTTP API to manage keys (keys are managed from the command line only).
- Changing the router-level `CourierWeb.ErrorJSON` (404/500 for unknown routes).

## Decisions

### Data model

`api_keys`: `id` (binary id), `name` (string, unique index), `token_hash` (binary, unique index), `scopes` (array of strings, non-empty), `revoked_at` (utc_datetime_usec, nullable), timestamps (utc_datetime_usec). Scopes are validated in the changeset against `~w(ingest read write)`; a check constraint `cardinality(scopes) > 0` backs it in the database.

Alternative: a join table for scopes. Rejected: three fixed values, no metadata; an array is simpler to query and to show.

### Token format and lookup

Token = `"ck_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)`. Stored value = `:crypto.hash(:sha256, token)`. Authentication hashes the presented token and looks it up by `token_hash` with `revoked_at IS NULL`.

- Lookup by hash means no comparison of secrets in application code, so no timing side channel on the token itself.
- SHA-256 without salt is enough because tokens have 256 bits of entropy; slow hashes (bcrypt, Argon2) protect low-entropy passwords and would only add latency to every request.
- The `ck_` prefix is fixed (not per key), so it identifies "a courier token" for secret scanners without exposing anything about a specific key.

### Context API (`Courier.Access`)

- `create_key(attrs) :: {:ok, %{key: ApiKey.t(), token: String.t()}} | {:error, Ecto.Changeset.t()}`
- `list_keys() :: [ApiKey.t()]` (ordered by `inserted_at`)
- `revoke_key(name) :: {:ok, ApiKey.t()} | {:error, :not_found}`; revoking an already revoked key keeps the original `revoked_at` and returns `{:ok, key}`.
- `authenticate(token) :: {:ok, ApiKey.t()} | {:error, :unauthorized}`
- `has_scope?(key, scope) :: boolean()`

`ApiKey` derives `Inspect` with `except: [:token_hash]` so the hash never shows up in logs or IEx output. The plaintext token is never put in the struct.

### Web layer

- `CourierWeb.Plugs.Authenticate`: reads `authorization`, accepts exactly `Bearer <token>` (scheme case-insensitive), calls `Courier.Access.authenticate/1`, assigns `:current_key`; otherwise halts with `401`, `www-authenticate: Bearer`, error code `unauthorized`.
- `CourierWeb.Plugs.RequireScope`: `plug RequireScope, :read`; halts with `403`, code `forbidden` when the key lacks the scope.
- Router: a new `scope "/api/v1", CourierWeb` piped through `[:api, :authenticated]`. Routes needing a scope add `RequireScope` in the controller with `plug ... when action in [...]` or in a dedicated pipeline; `GET /api/v1/me` needs only authentication.
- `CourierWeb.APIErrorJSON` renders `%{error: %{code:, message:}}`; `CourierWeb.FallbackController` maps `{:error, :unauthorized | :forbidden | :not_found}` and `{:error, %Ecto.Changeset{}}` (`422`, code `invalid`, with `details` holding field errors) to it. Both plugs render through `APIErrorJSON`, so the shape is the same everywhere.
- `MeController.show/2` renders `%{name:, scopes:}` from `conn.assigns.current_key`.

Alternative: `Plug.BasicAuth` or a single static admin token from the environment. Rejected by the ADR (no revocation, no names for the audit trail).

### Mix tasks

`mix courier.keys.create --name NAME --scopes read,write`, `mix courier.keys.list`, `mix courier.keys.revoke NAME`. They start the app (`Mix.Task.run("app.start")`) and call the context; errors print through `Mix.shell().error/1` and exit with `exit({:shutdown, 1})`. Scope strings are validated against the allowed list, never converted with `String.to_atom/1`. Tests use `Mix.shell(Mix.Shell.Process)` to capture output.

### Not leaking tokens

- Tokens travel only in the `authorization` header, which Phoenix does not log by default; the plugs never log the header or the token.
- Error messages are fixed strings and never include the presented value.
- A test captures logs (`ExUnit.CaptureLog`) during a rejected request and asserts the token is absent.

## Risks / Trade-offs

- [A leaked database dump exposes hashes] → Hashes of 256-bit random tokens cannot be reversed or brute-forced; revocation is immediate.
- [Every request does one indexed lookup] → Unique index on `token_hash`; fine at demo scale. A cache can come later if measurements need it.
- [Two error shapes coexist: router `ErrorJSON` (`errors.detail`) and API errors (`error.code`)] → Documented here; changing `ErrorJSON` would require modifying a protected test, so it waits for a change whose proposal says so.
- [Tokens in the dashboard's browser storage] → Accepted in the ADR for a local demo.

## Migration Plan

One additive migration creating `api_keys`. No existing data. Rollback drops the table.
