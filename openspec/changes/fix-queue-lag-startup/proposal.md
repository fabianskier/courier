# Proposal

## Why

Every boot logs `queue lag measurement failed` once (seen 2026-11-16, locally and in the Docker release). `Courier.Application` starts `CourierWeb.Telemetry` first, and its poller takes a first measurement at once; `Courier.Delivery.QueueLag.measure/0` queries the database through `Courier.Repo`, which has not started yet. The measurement rescues the error, so nothing breaks, but the warning is misleading and the first lag sample is lost.

## What Changes

- Start `CourierWeb.Telemetry` after `Courier.Repo`, so the first queue lag measurement runs with the database available. On shutdown the poller then stops before the repo.
- A test pins that order.
- Not in this change: anything else in the supervision tree, or how the measurement itself works.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `observability`: new requirement "Queue lag measured with the database up".

## Impact

- `lib/courier/application.ex` only, plus a new test file. No new dependencies; existing tests are not modified.
- Telemetry events emitted while the repo starts are unaffected: the metrics are attached by the dashboard and reporters, not by the poller's supervisor.
