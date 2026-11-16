# Proposal

## Why

Operators need to see which merchant endpoints are failing before merchants complain, and courier must prove that a failing endpoint does not slow down everyone else (FR-17, FR-36). One gap from `add-webhook-delivery` also needs closing: a delivery whose endpoint was disabled for good keeps its job in a stopped queue and stays `pending` forever, even after its retry window ends.

## What Changes

- **Consecutive failures**: each endpoint counts consecutive failed attempts (any attempt that is not `2xx`, including a rejected URL); a success resets the count. The count changes in the same transaction that stores the attempt.
- **Degraded flag**: when the count reaches the threshold (default 20, `config :courier, :degraded_threshold`), the endpoint gets `degraded_at` and a telemetry event `[:courier, :endpoint, :degraded]`; the next success clears it and emits `[:courier, :endpoint, :recovered]`. Deliveries keep retrying; the queue is not paused.
- **API**: endpoints render `consecutive_failures`, `degraded` and `degraded_at`; `GET /api/v1/endpoints?degraded=true` lists only degraded ones.
- **Window sweeper**: an Oban cron job (every 5 minutes, static queue `maintenance`) marks `failed` every `pending` delivery whose window has ended and cancels its job, so deliveries of a disabled endpoint, or with a lost job, reach a terminal state.
- **Isolation test**: with real Oban queues, an endpoint that hangs on every request does not delay the first attempt of another endpoint's delivery (FR-36, and the test the queue ADR asks for).
- Not in this change: metrics and dashboards for these events (step 6), pausing degraded endpoints.

## Capabilities

### New Capabilities
- `endpoint-health`: consecutive failures, the degraded flag and its telemetry, and isolation between endpoints.

### Modified Capabilities
- `webhook-endpoints`: endpoints show their health and can be filtered by it.
- `webhook-delivery`: pending deliveries past their window are failed by a periodic sweep.

## Impact

- Migration adding `consecutive_failures` and `degraded_at` to `endpoints`.
- `Courier.Delivery.record_attempt/3` updates the endpoint; new `Courier.Delivery.WindowSweeper` worker; `config/config.exs` gains the `maintenance` queue and `Oban.Plugins.Cron`.
- `EndpointJSON` and `EndpointController.index`.
- No new dependencies. Existing tests are not modified.
