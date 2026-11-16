# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected.

## 1. Resend

- [x] 1.1 Implement `Courier.Delivery.resend/2` as in design.md; verify with new tests in `test/courier/delivery/resend_test.exs` at the context level, named after the spec scenarios: "Resend a failed delivery" (with the job in the endpoint's queue), "Original unchanged", "Resend a skipped delivery", "Resend a resend", "Pending delivery", "Double resend", "Simultaneous resends" (two tasks in the sandbox's shared mode, as in the ingestion concurrency test), "Endpoint disabled", and an unknown id; and in `test/courier/delivery/resend_worker_test.exs` "Scenario: Same webhook id" by performing the resend's job against a `Req.Test` stub
- [ ] 1.2 Add `POST /api/v1/deliveries/:id/resend` with the `write` scope, the actor from `conn.assigns.current_key`, the `info` log line, the three fallback clauses, and the new fields in `DeliveryJSON` (with `get_delivery/1` preloading resends) and `EventJSON`, as in design.md; verify with new tests in `test/courier_web/controllers/delivery_resend_test.exs` over HTTP: "Scenario: Resend a failed delivery", "Scenario: Wrong scope", "Scenario: Pending delivery", "Scenario: Double resend", "Scenario: Endpoint disabled", "Scenario: Unknown delivery" (`404` for unknown and malformed ids) and "Scenario: Resend links", checking codes and that rejected requests create nothing

## 2. Docs

- [ ] 2.1 Document resend in `docs/architecture.md` (rules, status codes, actor format, links in the read API, a `curl` example) and mark step 5 done in `docs/roadmap.md` with `add-observability` (step 6) as next; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-manual-resend --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-manual-resend <task>` and review before merging.
- Archive after the last merge and check end to end: resend a failed delivery after fixing the receiver, and see the link both ways.
