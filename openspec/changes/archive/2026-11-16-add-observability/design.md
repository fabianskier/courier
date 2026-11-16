# Design

## Context

Events today: Phoenix, Ecto and VM metrics in `CourierWeb.Telemetry`; `[:courier, :endpoint, :degraded | :recovered]` from `Courier.Delivery.record_attempt/3` after commit; Oban's own `[:oban, :job, ...]`. LiveDashboard is mounted at `/dev/dashboard` only when `dev_routes` is set. The analysis allows "API keys and an admin token only" for auth; no admin token exists yet.

## Goals / Non-Goals

**Goals:** every event in FR-33 emitted exactly once, after commit, with ids as metadata and no payloads or secrets; a dashboard showing them; admin-only access in every environment.

**Non-Goals:** external metric storage, alerting, tracing.

## Decisions

### Events

| Event | Measurements | Metadata | Emitted by |
|---|---|---|---|
| `[:courier, :event, :ingested]` | `%{deliveries: n, pending: p}` | `merchant_id`, `type` | `Ingestion.ingest/2` after commit, new events only (not repeats) |
| `[:courier, :attempt, :start]` | `%{system_time}` | `delivery_id`, `endpoint_id`, `number` | worker, before the request |
| `[:courier, :attempt, :stop]` | `%{duration}` (native units), `%{since_created_ms}` | the above plus `outcome` (`:success`, `:retry`, `:give_up`), `status` (integer or `nil`), `status_class` (`"2xx"`… or `"error"`) | worker, after the request |
| `[:courier, :attempt, :exception]` | `%{duration}` | the start metadata plus `kind`, `reason` | worker, if the request raises |
| `[:courier, :delivery, :succeeded]` | `%{attempts: n, total_ms}` | `delivery_id`, `endpoint_id` | `record_attempt/3` after commit |
| `[:courier, :delivery, :failed]` | `%{attempts: n, total_ms}` | the above plus `reason` (`:non_retryable`, `:window_ended`) | `record_attempt/3` and `fail_without_attempt/2` after commit |
| `[:courier, :delivery, :retry_scheduled]` | `%{delay_seconds}` | `delivery_id`, `endpoint_id`, `attempt` | `record_attempt/3` after commit |
| `[:courier, :queue, :lag]` | `%{seconds, available}` | `queue` | `QueueLag.measure/0`, every 10 s |

`since_created_ms` is the time from the delivery's `inserted_at` to the attempt start; for `number == 1` it is the time to first attempt. `total_ms` is from `inserted_at` to `completed_at`. Attempt start/stop use `:telemetry.span/3` (telemetry ≥ 1.1 supports extra stop measurements by returning `{result, extra_measurements, stop_metadata}`). `Courier.Telemetry` holds the event names (`events/0`) and small `emit_*` helpers so names live in one place.

Emitting after commit: `record_attempt/3` already returns after the transaction; it gains the delivery transition in its result and emits next to the health events. `fail_without_attempt/2` emits `failed` with `reason: :window_ended` only when it changed the delivery (not for `:stale`).

### Queue lag

`Courier.Delivery.QueueLag.measure/0` runs one query: for queues starting with `endpoint:`, `count(*)` and `max(now() - scheduled_at)` over jobs in state `available`, grouped by queue; it emits one `[:courier, :queue, :lag]` per queue with jobs, and nothing for empty queues. `scheduled_at` is when a job became runnable (insertion or snooze end), so lag measures waiting, not backoff. It is registered in `CourierWeb.Telemetry`'s `periodic_measurements/0` (`{Courier.Delivery.QueueLag, :measure, []}`).

### Metrics (`CourierWeb.Telemetry.metrics/0`)

Added: `counter("courier.event.ingested.count", tags: [:type])`, `sum("courier.event.ingested.deliveries")`, `summary("courier.attempt.stop.duration", unit: {:native, :millisecond}, tags: [:outcome, :status_class])`, `counter("courier.attempt.stop.duration", tags: [:outcome])` (attempt count by outcome), `summary("courier.attempt.stop.since_created_ms", tags: [:number])` restricted to `number == 1` with `keep:`, `counter("courier.attempt.exception.duration")`, `counter("courier.delivery.succeeded.attempts")`, `counter("courier.delivery.failed.attempts", tags: [:reason])`, `summary("courier.delivery.succeeded.total_ms")`, `counter("courier.delivery.retry_scheduled.delay_seconds")`, `summary("courier.delivery.retry_scheduled.delay_seconds")`, `counter("courier.endpoint.degraded.consecutive_failures")`, `counter("courier.endpoint.recovered.count")` (via `event_name` + measurement fun), `last_value("courier.queue.lag.seconds", tags: [:queue])`, `last_value("courier.queue.lag.available", tags: [:queue])`. Exact names may be adjusted to Telemetry.Metrics rules, but each event in the table must have at least one metric.

### Admin dashboard

- `config :courier, :admin_token` from `COURIER_ADMIN_TOKEN` in `config/runtime.exs` (all environments; prod does not require it). `config/dev.exs` sets `"courier-dev-admin-token-not-a-secret"`; `config/test.exs` sets a fixed test token.
- `CourierWeb.Plugs.AdminAuth`: no token configured → `404` (route hidden). Otherwise `Plug.BasicAuth.parse_basic_auth/1`; the password is compared with `Plug.Crypto.secure_compare/2`; mismatch or missing → `Plug.BasicAuth.request_basic_auth/1` (`401` with `www-authenticate`). The user name is ignored. Never log the token or the `authorization` header.
- Router: a `:admin` pipeline (`:fetch_session`, `:protect_from_forgery`, `AdminAuth`) and `live_dashboard "/admin/dashboard", metrics: CourierWeb.Telemetry, ecto_repos: [Courier.Repo]` outside the `dev_routes` block; the `/dev/dashboard` block is removed. LiveDashboard's LiveView socket is already in `CourierWeb.Endpoint`.

## Risks / Trade-offs

- [Basic auth sends the token on every request] → Acceptable over HTTPS (prod forces it via the host's TLS); this is an operator tool, and real user auth would be a new ADR.
- [Many endpoints → many queue lag series] → `last_value` per queue is cheap in LiveDashboard; empty queues emit nothing.
- [Metrics live in memory only] → LiveDashboard shows recent data; exporting is a later change.

## Migration Plan

None.
