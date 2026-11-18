# Tasks

Each task must stay within the gate's diff budget (about 800 changed lines and 20 files, tests included). Existing test files are protected: put new tests in new files. Read design.md before each task. Tests are named after the spec (`describe "Requirement: …"`, `test "Scenario: …"`).

## 1. Retention

- [x] 1.1 Add `Courier.Retention` (`parse_days/1`, `prune/2` with the batch selection and the batched delete as in design.md) and `COURIER_RETENTION_DAYS` in `config/runtime.exs` (default 30, minimum 2, boot error); verify with new tests in `test/courier/retention_test.exs` covering every scenario of "Retention period", "Old finished events are pruned", "Deletion respects append-only attempts" and "Idempotency keys after pruning"
- [x] 1.2 Add `Courier.Retention.Worker`, its daily cron entry in the `maintenance` queue, the `[:courier, :retention, :pruned]` telemetry event and log line, and the LiveDashboard metrics; document retention in `docs/architecture.md` (a "Retention" section), state in the README that a pruned event's idempotency key can be reused and how to set `COURIER_RETENTION_DAYS`, and mark step 13 done in `docs/roadmap.md` with step 14 next; verify with new tests in `test/courier/retention_worker_test.exs` covering every scenario of "Daily job and report", and that `sh .smelt/checks.sh` and `openspec validate add-retention --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-retention <task> --model opus`; review and merge each task before starting the next.
- After the last merge, archive the change.
