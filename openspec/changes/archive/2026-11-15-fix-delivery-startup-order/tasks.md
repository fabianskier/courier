# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests in new files: existing files under `test/` are protected.

## 1. Startup order

- [x] 1.1 Reorder the children in `Courier.Application` as in design.md, moving their comments with them; verify with a new test file `test/courier/application_order_test.exs` (`describe "Requirement: Delivery dependencies outlive delivery jobs"`, `test "Scenario: Supervision order"`) that checks the order through `Supervisor.which_children(Courier.Supervisor)`; check that the test fails on the current order before keeping the change; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate fix-delivery-startup-order --strict` pass

## Workflow follow-up

- Build with `mix smelt.task ~/code/courier fix-delivery-startup-order 1.1`, review, merge and archive.
