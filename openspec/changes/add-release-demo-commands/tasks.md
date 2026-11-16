# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests in new files: existing files under `test/` are protected and must pass unchanged.

## 1. Simulator from the release

- [ ] 1.1 Add `CourierDemo.CLI` with `parse_simulate/2`, `summary/1` and `simulate/1` as in design.md, make `Mix.Tasks.Courier.Simulate` delegate its parsing, validation and summary to it (same messages and exit behaviour), and add the executable `rel/overlays/bin/simulate`; verify with new tests in `test/courier_demo/cli_simulate_test.exs`: "Scenario: Release run prints the summary", "Scenario: Release run rejects invalid options" and "Scenario: Release run reads the token from the environment", and that `test/mix/tasks/courier_simulate_test.exs` passes unchanged; then document `bin/simulate` in the "Producer simulator" section of `docs/architecture.md`

## 2. Seeds from the release

- [ ] 2.1 Add `CourierDemo.Seeds.report/2` (`:mix` default, `:release`) and `CourierDemo.CLI.seed/0` as in design.md, and the executable `rel/overlays/bin/seed`; verify with new tests in `test/courier_demo/cli_seed_test.exs`: "Scenario: Release output ready to use", "Scenario: Release second run refused" and "Scenario: Release receiver unreachable", and that `test/courier_demo/seeds_test.exs` passes unchanged; then document `bin/seed` in the "Demo seeds" section of `docs/architecture.md`

## 3. Docker-only walkthrough

- [ ] 3.1 Replace the README's "With Docker" paragraph with a short walkthrough that needs only Docker (`docker compose up -d --build`, `docker compose exec courier bin/seed`, the printed `docker compose exec courier bin/simulate` command, `docker compose logs -f demo-receiver`, the dashboard password from `compose.yaml`, and `http://demo-receiver:4001/hooks/harbor-fail/ok` as the URL for the resend step), update the commands in "Docker demo" of `docs/architecture.md`, and mark step 7c done in `docs/roadmap.md` with `add-mcp-server` as next; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-release-demo-commands --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-release-demo-commands <task>` and review before merging.
- After the last merge, follow the README's Docker walkthrough on a fresh volume (`docker compose down -v` first): `bin/seed` prints a command that runs as printed, `bin/simulate` prints its summary, and the receiver logs `signature=valid`. Then archive.
