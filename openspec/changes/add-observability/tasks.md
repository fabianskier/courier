# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected.

## 1. Events

- [x] 1.1 Add `Courier.Telemetry` (event names and emit helpers) and emit `[:courier, :event, :ingested]` from `Courier.Ingestion` and the delivery outcome events (`succeeded`, `failed`, `retry_scheduled`) from `Courier.Delivery.record_attempt/3` and `fail_without_attempt/2`, after commit, as in design.md; verify with new tests in `test/courier/telemetry/ingestion_telemetry_test.exs` ("Scenario: New event emits ingested", "Scenario: Repeat emits nothing") and `test/courier/telemetry/delivery_telemetry_test.exs` ("Scenario: Succeeded", "Scenario: Failed for good", "Scenario: Window ended", "Scenario: Retry scheduled", and nothing emitted for a stale result), attaching handlers with `:telemetry.attach_many/4` and detaching on exit
- [x] 1.2 Emit the attempt events from `Courier.Delivery.Worker` with `:telemetry.span/3` as in design.md; verify with new tests in `test/courier/telemetry/attempt_telemetry_test.exs` using `Req.Test` stubs: "Scenario: Attempt start and stop", "Scenario: Network error", and a check that no metadata value contains the payload, the response body or the signature
- [x] 1.3 Implement `Courier.Delivery.QueueLag.measure/0` and register it in `CourierWeb.Telemetry`'s periodic measurements, as in design.md; verify with new tests in `test/courier/telemetry/queue_lag_test.exs`: "Scenario: Waiting jobs measured" (jobs inserted with `Oban.insert/2` and `scheduled_at` set in the past) and "Scenario: Empty queues are silent", plus a non-endpoint queue ignored

## 2. Dashboard

- [x] 2.1 Add the metrics to `CourierWeb.Telemetry.metrics/0`, `CourierWeb.Plugs.AdminAuth`, the `:admin` pipeline and `/admin/dashboard` route (removing `/dev/dashboard`), and the `:admin_token` config in `config/runtime.exs`, `config/dev.exs` and `config/test.exs`, as in design.md; verify with new tests in `test/courier_web/admin_dashboard_test.exs` ("Scenario: Correct token" following the redirect LiveDashboard answers with, "Scenario: Missing or wrong token", "Scenario: Dashboard disabled" with the token removed from the app env for the test in an `async: false` module and restored on exit, and the token absent from captured logs) and `test/courier_web/telemetry_metrics_test.exs` ("Scenario: Metrics defined")

## 3. Docs

- [ ] 3.1 Document observability in `docs/architecture.md` (event table, metrics, queue lag, how to open the dashboard in dev and set `COURIER_ADMIN_TOKEN` in prod), add the token to "Security notes", and mark step 6 done in `docs/roadmap.md` with `add-demo-tools` (step 7) as next; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-observability --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-observability <task>` and review before merging.
- Archive after the last merge and check end to end: open the dashboard in dev with the token, send events to a receiver, and see the courier metrics move.
