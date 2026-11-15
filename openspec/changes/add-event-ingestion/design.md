# Design

## Context

Existing pieces this change builds on: `Courier.Access` and the `Authenticate`/`RequireScope` plugs, `Courier.Merchants`, `Courier.Endpoints` (with `EventFilter.matches?/2` and each endpoint's `retry_window_seconds`), `Courier.Pagination` (keyset, oldest first) and `CourierWeb.FallbackController`. Accepted ADRs that apply: "PostgreSQL as the only data store" (event, deliveries and later jobs in one transaction), "Deliveries with append-only attempts; resend creates a new delivery" (delivery model), "Event-type filters per endpoint". Requirements are in `specs/event-ingestion/spec.md`.

## Goals / Non-Goals

**Goals:**
- `Courier.Ingestion.ingest/2`: one function that validates, deduplicates and stores an event with its deliveries atomically, returning whether it was new or a repeat.
- The `deliveries` table in the shape the delivery change needs, so step 4 only adds columns it alone uses (attempts, degraded state).

**Non-Goals:**
- Oban jobs for pending deliveries: the delivery change adds an `Oban.insert` step to the same `Ecto.Multi`.
- Attempts, resend, retention.

## Decisions

### Tables

- `events`: `id` (binary id), `idempotency_key` (string, unique index), `request_hash` (binary, 32 bytes), `merchant_id` (references merchants, `on_delete: :restrict`), `type` (string), `payload` (jsonb, map), `occurred_at` and `received_at` (utc_datetime_usec), timestamps. Indexes on `(merchant_id, inserted_at)`, `(type)` and `(inserted_at, id)`.
- `deliveries`: `id`, `event_id` (references events), `endpoint_id` (references endpoints), `status` (string, check constraint `status IN ('pending','skipped','succeeded','failed')`), `attempt_count` (integer, default 0), `window_ends_at` (utc_datetime_usec, null for skipped), `next_attempt_at` (nullable), `completed_at` (nullable; set to the receipt time for skipped deliveries), `resend_of_id` (references deliveries, nullable), `triggered_by` (string, default `"system"`), timestamps. Unique index on `(event_id, endpoint_id) WHERE resend_of_id IS NULL`. Index on `(endpoint_id, status)`.

### Request hash

`request_hash = :crypto.hash(:sha256, :erlang.term_to_binary({type, merchant_id, payload, occurred_at_as_sent}, [:deterministic]))`. The payload is the decoded JSON (maps), so the `:deterministic` option makes key order irrelevant. `occurred_at_as_sent` is the string the producer sent, or `nil`; a repeat must send the same thing. Alternative: canonical JSON encoding; rejected because Jason does not sort keys and a hand-written canonicalizer is more code to trust.

### Ingestion flow (`Courier.Ingestion.ingest(attrs, idempotency_key)`)

1. Validate the key (`~r/\A[\x21-\x7E]{1,255}\z/`), the type (new `EventFilter.valid_type?/1`: an exact pattern without wildcard), the payload (a map) and `occurred_at`; compute the payload's JSON size (`Jason.encode!/1`) and return `{:error, :payload_too_large}` above 262 144 bytes.
2. Load the merchant: missing → changeset error on `merchant_id`; disabled → `{:error, :merchant_disabled}`.
3. In one `Ecto.Multi`, run by `Repo.transact/1`:
   - insert the event with `on_conflict: :nothing, conflict_target: :idempotency_key, returning: true`;
   - if nothing was inserted (the key exists), stop the Multi with `{:error, :duplicate}`; the caller then loads the stored event (committed by the winner) and compares hashes: equal → `{:ok, :repeat, event}`, different → `{:error, :idempotency_key_reused}`;
   - otherwise load the merchant's enabled endpoints and insert all deliveries with `Repo.insert_all` (status from `EventFilter.matches?/2`, `window_ends_at = received_at + retry_window_seconds` for pending, `completed_at = received_at` for skipped).
4. Return `{:ok, :created, event}` with deliveries preloaded.

`ingest_multi/…` is public (`@doc false`) so a test can append a failing step and prove that nothing is stored (scenario "Failure while storing deliveries"). With PostgreSQL's default isolation, `ON CONFLICT DO NOTHING` waits for a concurrent transaction that inserted the same key and then skips, so the loser sees the committed winner. Tests run the concurrent scenario with `Task.async_stream` in the sandbox's shared mode; requests then share one connection and are serialized, which exercises the conflict path but not true parallelism; the unique index guarantees the rest.

### Pagination order

`Courier.Pagination.paginate/2` gains an optional `order: :desc` (default `:asc`): same cursor format, reversed ordering and comparison. Events list newest first; merchants and endpoints keep oldest first.

### Web layer

- `EventController.create`: reads the `idempotency-key` header (missing → `nil`, which fails validation), takes only `type`, `merchant_id`, `payload`, `occurred_at` from the body, answers `202` for `:created` and `200` for `:repeat` with `EventJSON.show` (event plus deliveries: `id`, `endpoint_id`, `status`, `window_ends_at`).
- `index` (filters `merchant_id`, `type`; malformed `merchant_id` → empty page) and `show` (`404` for unknown or malformed ids).
- Scopes: `ingest` for create, `read` for index and show.
- `FallbackController` gains `:merchant_disabled` → `422 merchant_disabled`, `:idempotency_key_reused` → `422 idempotency_key_reused`, `:payload_too_large` → `413 payload_too_large`.
- `Plug.Parsers` gets `length: 1_048_576` as an outer bound on any request body; larger bodies are rejected by Phoenix before reaching the controller (rendered by the default `ErrorJSON`, which keeps its protected shape).

### Test support

`test/support/log_capture.ex` (`CourierWeb.LogCapture.capture_debug_log/1`) lowers the primary log level to `:debug` only while the function runs and restores it, as in `endpoint_secret_logging_test.exs`; tests using it must be `async: false`. A new `test/courier_web/plugs/token_logging_test.exs` uses it for the `api-access` scenario "Rejected token not echoed" and asserts the captured log is not empty.

## Risks / Trade-offs

- [A repeat that sends `occurred_at` explicitly when the original omitted it is treated as a reused key] → Documented: repeats must be byte-for-byte the same request apart from JSON key order.
- [Idempotency keys are global, not per merchant] → One producer in v1 (analysis); a multi-producer version would scope keys by key owner in a new ADR.
- [Large fan-out (many endpoints) inserts many rows in the request] → `insert_all` in one statement; fine at demo scale.

## Migration Plan

Two additive migrations (`events`, then `deliveries`). Rollback drops them in reverse order.
