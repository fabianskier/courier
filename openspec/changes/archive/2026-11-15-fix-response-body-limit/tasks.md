# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected.

## 1. Bound the response

- [x] 1.1 In `Courier.Delivery.Client`, stream the response with an `into:` function that halts after 4096 bytes, add `post/4` with options merged over the defaults and config (`:deadline`, default 30 000 ms, and `plug: nil` to bypass the `Req.Test` plug), and run each request under a new `Courier.Delivery.TaskSupervisor` with the deadline, as in design.md; keep `post/3` working for the worker. Update "HTTP client" in `docs/architecture.md` (streaming limit and total deadline). Verify with a new test file `test/courier/delivery/client_streaming_test.exs` (`describe "Requirement: Bounded response reading"`) against a local Bandit server: "Scenario: Large response body" (the server records that fewer than all 2,560 chunks were sent) and "Scenario: Body that trickles in" (with a short `:deadline`, asserting `{:error, "timeout"}` well before the server's sleep ends); check that both tests fail on the current client before keeping the change; verify every existing test passes unchanged, `mix precommit`, `sh .smelt/checks.sh` and `openspec validate fix-response-body-limit --strict` pass

## Workflow follow-up

- Build with `mix smelt.task ~/code/courier fix-response-body-limit 1.1` and review before merging.
- Archive the change after merge, then propose `add-endpoint-health`.
