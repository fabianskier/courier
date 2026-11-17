# Tasks

## 1. Startup order

- [x] 1.1 Move `CourierWeb.Telemetry` after `Courier.Repo` in `Courier.Application`'s children, with a comment saying why; verify with a new `test/courier/telemetry_order_test.exs` ("Scenario: Telemetry starts after the repo", reading `Supervisor.which_children(Courier.Supervisor)` like `application_order_test.exs`), that the existing tests pass unchanged, and that `sh .smelt/checks.sh` and `openspec validate fix-queue-lag-startup --strict` pass

## Workflow follow-up

- After the merge, start the server (`mix phx.server`) and check the log has no `queue lag measurement failed` line, then archive.
