# Tasks

Each task must stay within the gate's diff budget (about 800 changed lines and 20 files, tests included). Existing test files are protected: put new tests in new files. Read design.md before each task. Tests are named after the spec (`describe "Requirement: …"`, `test "Scenario: …"`).

## 1. Load command

- [x] 1.1 Add the `:latencies` option to `CourierDemo.Simulator.run/2`, `CourierDemo.Load` (options, sending, waiting, the delivery query, the report) and `CourierDemo.Load.Stats`, `CourierDemo.CLI.load/1`, `mix courier.load` and the executable `rel/overlays/bin/load`, as in design.md; verify with new tests in `test/courier_demo/load_stats_test.exs` and `test/courier_demo/load_test.exs` covering every scenario of `specs/load-test/spec.md`

## 2. README

- [x] 2.1 Polish the README: add the containers diagram and the delivery lifecycle diagram (Mermaid, from `docs/architecture.md`) near the top, a "Measured performance" section that explains `bin/load` / `mix courier.load` and points at the NFR table in `docs/analysis.md`, and check every walkthrough command against the code; add a "Load test" paragraph to `docs/architecture.md` ("Demo tools"); verify `sh .smelt/checks.sh` and `openspec validate add-load-test --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build 1.1 with `mix smelt.task ~/code/courier add-load-test 1.1 --model opus` and 2.1 with `--model sonnet`; review and merge each before the next.
- After the last merge, run `bin/load` in the Docker demo (50 events/s for the latency target, then higher rates for throughput, and all merchants for isolation), write the measured values into the NFR table of `docs/analysis.md`, mark step 14 done in `docs/roadmap.md`, and archive the change.
