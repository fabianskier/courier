# Design

## Context

Existing pieces this change builds on: `Courier.Ingestion` (`ingest_multi/2` stores the event and its deliveries with `Repo.transact/1`), `Courier.Delivery.Delivery` (statuses, `attempt_count`, `next_attempt_at`, `window_ends_at`, `completed_at` already exist), `Courier.Endpoints` (`signing_secrets/2`, `retry_on_4xx`, `max_concurrency` 1 to 50), `Courier.Endpoints.UrlPolicy.check/2`, Oban 2.24 with no static queues and `testing: :manual` in tests. Accepted ADRs that apply: "Oban with one queue per endpoint schedules deliveries and is the only layer that retries", "Deliveries with append-only attempts; resend creates a new delivery", "Sign webhooks with the Standard Webhooks scheme", "Retention: prune by age, with a controlled exception to append-only" (the trigger's exception). Retry timing follows `docs/architecture.md` ("Retry timing"). Requirements are in `specs/`.

## Goals / Non-Goals

**Goals:**
- A pending delivery is sent, retried and finished with no human action, and every attempt is stored.
- Each piece that decides something (signature, classification, delay, window) is a pure function tested on its own; the worker only wires them.

**Non-Goals:**
- `degraded` flag, consecutive failure count and the isolation test with a slow endpoint (`add-endpoint-health`).
- Resend, retention job, telemetry beyond Oban's.
- Pinning the resolved IP for the connection (see Risks).

## Decisions

### Signer (`Courier.Delivery.Signer`)

`headers(event_id, timestamp_seconds, body, secrets)` returns `[{"webhook-id", event_id}, {"webhook-timestamp", "<unix seconds>"}, {"webhook-signature", "v1,<sig1> v1,<sig2>"}]`, where each signature is `Base.encode64(:crypto.mac(:hmac, :sha256, key, "#{id}.#{ts}.#{body}"))` and `key` is the base64-decoded part after `whsec_`. Secrets come from `Endpoints.signing_secrets/2` (current first). Checked with the Standard Webhooks test vector: secret `whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw`, id `msg_p5jXN8AQM9LWM0D4loKWxJek`, timestamp `1614265330`, body `{"test": 2432232314}` → `v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=`.

### Request body

`{"id": event.id, "type": event.type, "timestamp": occurred_at (ISO 8601), "merchant_id": ..., "data": payload}`, encoded once per attempt; the signature covers exactly the bytes sent. Headers also carry `content-type: application/json`, `user-agent: courier/<version>` and `courier-delivery-id`.

### HTTP client (`Courier.Delivery.Client`)

`post(url, body, headers)` calls `Req.post/2` with `retry: false`, `redirect: false`, `decode_body: false`, `connect_options: [timeout: 5_000]`, `receive_timeout: 15_000`, `finch: Courier.Finch`, plus `Application.get_env(:courier, Courier.Delivery.Client, [])` merged in (tests set `plug: {Req.Test, Courier.Delivery.Client}`). It returns `{:ok, %{status, retry_after, body}}` (body: first 4096 bytes, invalid UTF-8 and NUL bytes replaced so it fits a `text` column) or `{:error, reason}` with a short string (`"timeout"`, `"econnrefused"`, …). `Courier.Finch` is started in `Courier.Application` with `pools: %{default: [size: 50]}`; Finch creates one pool per origin, so each origin has at least the maximum `max_concurrency`.

### Retry policy (`Courier.Delivery.RetryPolicy`)

- `classify(result, retry_on_4xx)`: `2xx` → `:success`; `{:error, _}`, `408`, `429`, `5xx` → `:retry`; `3xx` → `:give_up`; other `4xx` → `:retry` if `retry_on_4xx`, else `:give_up`.
- `delay(n, retry_after, rand \\ &:rand.uniform/1)` in seconds for attempt `n` ≥ 1: `1 + random(0, min(3600, 10 * 2^(n-1)))`; with a `Retry-After` (only kept for `429` and `503`), `max(that, retry_after)` capped at 3600. `rand` is injectable so tests are deterministic.
- `parse_retry_after(value, now)`: delta seconds or an HTTP date; anything else → `nil`.
- `next(now, delay, window_ends_at)`: `{:retry_at, at}` if `now + delay` is before the window end, else `:window_ended`.

### Attempts (`Courier.Audit`)

- Table `attempts`: `id`, `delivery_id` (references deliveries, `on_delete: :restrict`), `number` (integer), `started_at`, `duration_ms`, `url`, `request_headers` (jsonb map), `response_status` (nullable), `response_body` (text, nullable), `error` (nullable), `inserted_at` only. Unique index `(delivery_id, number)`.
- Trigger function `attempts_append_only()` `BEFORE UPDATE OR DELETE`: raises on `UPDATE`; on `DELETE` raises unless `current_setting('courier.retention', true) = 'on'`.
- `request_headers` stores every header sent except that `webhook-signature` is replaced by `"[redacted]"`.
- `Courier.Audit.list_attempts(delivery_id)` returns attempts by `number`. The schema has no update changeset.

### Recording an outcome (`Courier.Delivery.record_attempt/3`)

`record_attempt(delivery_id, attempt_attrs, transition)` runs in one transaction: lock the delivery (`FOR UPDATE`); if it is no longer `pending`, insert nothing and return `{:ok, :stale}`; otherwise insert the attempt with `number = attempt_count + 1` and update the delivery: `{:succeeded, now}` / `{:failed, now}` set `status` and `completed_at` and clear `next_attempt_at`; `{:retry_at, at}` sets `next_attempt_at`. `fail_without_attempt(delivery_id, now)` marks a pending delivery `failed` when its window ended before any further attempt. The lock is never held during the HTTP request.

### Worker (`Courier.Delivery.Worker`)

`use Oban.Worker, max_attempts: 10` (a safety net for crashes; snoozes do not consume attempts, the window is the stop rule). Args: `%{"delivery_id" => id}`. `perform/1`:

1. Load the delivery with its endpoint and event. Not `pending` → `:ok`.
2. `now >= window_ends_at` → `fail_without_attempt`, `:ok`.
3. Endpoint disabled → `{:snooze, 60}` (its queue is normally stopped; this covers the race).
4. `UrlPolicy.check(url)`: a rejected address (`:private_address` and other policy errors) → attempt with `error: "url_rejected: <reason>"`, `:give_up`; a resolution failure → attempt with `error: "dns: <reason>"`, `:retry`.
5. Sign and send; time the request with `System.monotonic_time/0`.
6. Classify, compute the delay and `next`, call `record_attempt`, and return `:ok` or `{:snooze, seconds}`.

### Queues (`Courier.Delivery.Queues` and `Courier.Delivery.QueueManager`)

- `Queues.name(endpoint_id)` → `"endpoint:<id>"`; jobs are inserted with that `queue`.
- `QueueManager` is a GenServer started after Oban. On init it reads enabled endpoints and starts their queues with `local_only: true`. `sync(endpoint)` (called by `Endpoints.create_endpoint/1` and `update_endpoint/2` after a successful write) starts the queue or scales it to `max_concurrency` when the endpoint is enabled, and stops it when disabled, for all nodes.
- Oban calls go through a module from config (`:queue_control`, default `Courier.Delivery.ObanQueueControl` with `start/2`, `scale/2`, `stop/1`); tests use a stub that sends messages to the test process, because `testing: :manual` runs no queues.

### Ingestion changes

- `ingest_multi/2` appends `Oban.insert_all(:jobs, fn %{deliveries: ds} -> ... end)` with one `Worker.new(%{delivery_id: id}, queue: Queues.name(endpoint_id))` per pending delivery.
- Disabled merchant: before returning `:merchant_disabled`, look up the key; if an event exists, answer as a repeat (`{:ok, :repeat, event}` or `:idempotency_key_reused`).
- Delivery order everywhere (create response, repeat and read): join the endpoint and order by `endpoint.inserted_at, endpoint.id, delivery.inserted_at, delivery.id`.

### Read API

`GET /api/v1/deliveries/:id` (scope `read`) → `{"data": {id, event_id, endpoint_id, status, attempt_count, next_attempt_at, window_ends_at, completed_at, attempts: [{number, started_at, duration_ms, url, response_status, response_body, error}]}}`; `404 not_found` for unknown or malformed ids. Request headers are not rendered.

## Risks / Trade-offs

- [DNS rebinding: the policy resolves the host, then Req resolves it again] → Accepted for v1 and documented in Security notes; pinning the checked IP (connect to the address with the original host for TLS SNI) is a later hardening change.
- [Deliveries of an endpoint disabled for good stay `pending` with a stopped queue] → Visible in the API; `add-endpoint-health` or retention decides what happens to them.
- [Queue limits are per node] → As in the ADR; single node in v1.
- [A job may run twice (at-least-once) if a node dies after the request] → Receivers deduplicate by `webhook-id`, as Standard Webhooks expects; `record_attempt` ignores a delivery that is no longer pending.

## Migration Plan

One additive migration (`attempts` with its trigger function). Rollback drops the trigger, the function and the table.
