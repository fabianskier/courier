# Proposal

## Why

Operators need to see what courier is doing without reading the database: how many events arrive, how attempts end and how long they take, how many deliveries fail or are retried, which endpoints are degraded, and whether queues are falling behind (FR-33). The numbers must be visible in a dashboard that only an admin can open (FR-34), and they are the inputs of the load test in step 14.

## What Changes

- **Telemetry events** (all under `[:courier, ...]`, emitted after the data is committed): event ingested; attempt start, stop (outcome, status, duration) and exception; delivery succeeded, failed (with reason) and retry scheduled (delay); and queue lag, measured every 10 seconds per endpoint queue. The existing endpoint degraded/recovered events stay as they are.
- **Metrics**: `CourierWeb.Telemetry` defines counters and summaries for those events, tagged where useful (outcome, status class, reason, queue), including the time from a delivery's creation to its first attempt (the NFR "time to first attempt").
- **Admin dashboard**: Phoenix LiveDashboard at `/admin/dashboard` in every environment, behind HTTP Basic auth whose password is the admin token (`COURIER_ADMIN_TOKEN`; any user name). Without a configured token the route answers `404`. Development uses a fixed, non-secret token; the `/dev/dashboard` route is replaced.
- Not in this change: exporting metrics to Prometheus or another backend, alerts, retention telemetry (step 13).

## Capabilities

### New Capabilities
- `observability`: the telemetry events, the metrics and the admin dashboard.

### Modified Capabilities
None.

## Impact

- New `Courier.Telemetry` (event names and helpers) and `Courier.Delivery.QueueLag`; calls added in `Courier.Ingestion`, `Courier.Delivery` and `Courier.Delivery.Worker`.
- `CourierWeb.Telemetry` (metrics and the periodic measurement), new `CourierWeb.Plugs.AdminAuth`, router, `config/dev.exs`, `config/test.exs`, `config/runtime.exs`.
- No new dependencies (`telemetry`, `telemetry_metrics`, `telemetry_poller` and `phoenix_live_dashboard` are already in `mix.exs`). Existing tests are not modified.
