# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected.

## 1. Health

- [x] 1.1 Generate the `add_health_to_endpoints` migration, add the fields to `Courier.Endpoints.Endpoint` (not cast), and update `Courier.Delivery.record_attempt/3` to count failures, set and clear `degraded_at` and emit the telemetry events after commit, as in design.md; verify with new tests in `test/courier/delivery/endpoint_health_test.exs` (threshold set to 3 for the test with `Application.put_env` in an `async: false` module, restored on exit; events captured with `:telemetry.attach_many/4`): "Scenario: Failures counted and reset", "Scenario: No attempt, no count", "Scenario: Endpoint becomes degraded", "Scenario: Further failures emit no new event", "Scenario: Endpoint recovers" and, through the worker with a `Req.Test` stub, "Scenario: Degraded endpoint still retried"
- [x] 1.2 Render `consecutive_failures`, `degraded` and `degraded_at` in `EndpointJSON`, and add the `degraded` filter to `Endpoints.list_endpoints/1` and `EndpointController.index`, as in design.md; verify with new tests in `test/courier_web/controllers/endpoint_health_api_test.exs`: "Scenario: Health in the response" and "Scenario: List degraded endpoints" (also `degraded=false`, and an invalid value ignored)

## 2. Sweep and isolation

- [ ] 2.1 Implement `Courier.Delivery.WindowSweeper` and configure `Oban.Plugins.Cron` and the `maintenance` queue in `config/config.exs`, as in design.md; verify with new tests in `test/courier/delivery/window_sweeper_test.exs` using `perform_job/2`: "Scenario: Delivery of a disabled endpoint expires", "Scenario: Pending delivery inside its window is kept", already terminal deliveries untouched, and a batch limit that re-enqueues the sweeper
- [ ] 2.2 Add the isolation test `test/courier/delivery/endpoint_isolation_test.exs` (`describe "Requirement: Endpoints are isolated from each other"`, `test "Scenario: Slow endpoint does not delay another"`) as in design.md, with any test-only support module in a new file under `test/support/`; change application code only if the test exposes a real isolation bug, and say so; verify the test passes ten times in a row (`mix test --repeat-until-failure 10` or a loop) so it is not flaky

## 3. Docs

- [ ] 3.1 Document endpoint health (counting, threshold and its config, telemetry events, API fields and filter), the window sweeper and the isolation guarantee in `docs/architecture.md`; resolve the open question on N in `docs/analysis.md` (default 20, global, configurable); mark step 4b done in `docs/roadmap.md` with `add-manual-resend` (step 5) as next; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-endpoint-health --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-endpoint-health <task>` and review before merging.
- Archive after the last merge and check end to end: an endpoint failing until degraded, then recovering.
