# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected. Tests compute signatures with their own HMAC code, never with `Courier.Delivery.Signer`.

## 1. Demo receiver

- [x] 1.1 Add `CourierDemo.Receiver` (`Plug.Router`: `PUT /_secrets/:name`, `POST /hooks/:name/:behaviour`, `404` otherwise), `CourierDemo.Receiver.Secrets` (`Agent`) and `CourierDemo.Receiver.child_spec/1` (secrets agent plus Bandit), with the independent signature check, the options and the log line as in design.md; verify with new tests in `test/courier_demo/receiver_test.exs`, starting the receiver with `start_supervised!/1` on port 0 and calling it with `Req`: "Scenario: Each behaviour answers as named", "Scenario: Timeout answers late", "Scenario: Unknown behaviour", "Scenario: Secret registered", "Scenario: Invalid secret rejected", "Scenario: Wrong signature rejected", "Scenario: Stale timestamp rejected", "Scenario: Rotation overlap accepted", "Scenario: Unchecked request" and "Scenario: Log without secrets" (with `CourierWeb.LogCapture.capture_debug_log/1`)
- [ ] 1.2 Add `CourierDemo.Receiver.serve/1` and `mix courier.demo.receiver [--port] [--ip]` (does not start the courier application; reads `COURIER_DEMO_TIMEOUT_MS`), as in design.md; verify with a new `test/courier_demo/receiver_delivery_test.exs` (`async: false`, `URLPolicy` and `Client` config overridden as in `endpoint_isolation_test.exs`) where `Courier.Delivery.Worker` delivers to a real receiver with the endpoint's secret registered: "Scenario: Valid signature accepted" (attempt `200`, delivery `succeeded`); then add a "Demo tools" section to `docs/architecture.md` describing the receiver (paths, signature check, secret registration, how to start it), replace `demo/receiver/` with `lib/courier_demo/` in "Code layout", and add the registration route to "Security notes"

## 2. Producer simulator

- [ ] 2.1 Add `CourierDemo.Simulator` (`plan/2` with an injectable random function, `run/2` with scheduled sends and a tally) and `mix courier.simulate` (option parsing, validation, summary; does not start the courier application), with `req_options` from `config :courier, CourierDemo.Simulator` and `plug: {Req.Test, CourierDemo.Simulator}` in `config/test.exs`, as in design.md; verify with new tests in `test/courier_demo/simulator_test.exs` and `test/mix/tasks/courier_simulate_test.exs`: "Scenario: Missing merchant", "Scenario: Invalid rate", "Scenario: New events sent", "Scenario: Rate respected", "Scenario: Repeats reuse key and body", "Scenario: No repeats" and "Scenario: Summary printed"; then document the simulator (options, repeats, summary, an example) in the "Demo tools" section of `docs/architecture.md`

## 3. Demo seeds

- [ ] 3.1 Add `CourierDemo.Seeds.run/1` and call it from `priv/repo/seeds.exs`, with the data set in design.md, secret registration after creation (`req_options` from `config :courier, CourierDemo.Seeds`, `plug: {Req.Test, CourierDemo.Seeds}` in `config/test.exs`) and the printed summary; verify with new tests in `test/courier_demo/seeds_test.exs` using `https://receiver.public.test` as the receiver URL: "Scenario: Data created", "Scenario: Receiver URL from the environment", "Scenario: Secrets registered", "Scenario: Receiver unreachable" (stub answering with a transport error), "Scenario: Output ready to use" and "Scenario: Second run refused"; then document the seeds (the table of merchants and endpoints, `COURIER_DEMO_RECEIVER_URL`, seeding once) in the "Demo tools" section of `docs/architecture.md`

## 4. Demo walkthrough

- [ ] 4.1 Add a "Local demo" section to `README.md` (start Postgres, `mix courier.demo.receiver`, `mix ecto.reset`, `mix phx.server`, the printed `mix courier.simulate` command, what to look for in `GET /api/v1/deliveries/:id` and on `/admin/dashboard`, and resending after switching `harbor-fail`'s URL to `/ok`), update its status line, and mark step 7 done in `docs/roadmap.md` with a new manual step 7b (Docker image with `mix phx.gen.release --docker`, `courier` and `demo-receiver` services in `compose.yaml`) as next; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-demo-tools --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-demo-tools <task>` and review before merging.
- Archive after the last merge and check end to end by following the README's "Local demo" section on a fresh database: deliveries succeed, retry, dead-letter after 5 minutes, get skipped by the filter, and the slow endpoint does not delay the others.
