# Proposal

## Why

The Docker demo (roadmap step 7b) starts courier, PostgreSQL and the demo receiver from one release image, but a release has no Mix: the seeds need a hand-typed `bin/courier rpc` expression and the simulator still needs Elixir on the host. A reviewer with only Docker should run the whole demo.

## What Changes

- **Simulator from the release**: a `bin/simulate` command in the release takes the same options as `mix courier.simulate`, with the same validation, messages and summary. The option parsing and the summary move out of the Mix task into `lib/courier_demo/`, so both entry points share them; `mix courier.simulate` behaves as before.
- **Seeds from the release**: a `bin/seed` command runs the demo seeds inside the running release and prints the same report, with commands that work in the Docker demo (`docker compose exec courier bin/simulate ...`, and how to start again from an empty database) instead of the Mix ones.
- **Docs**: the README's "With Docker" paragraph becomes a walkthrough that needs only Docker; "Docker demo" in `docs/architecture.md` and the roadmap are updated.
- **Not in this change**: seeding automatically on `docker compose up`, a release command for the receiver (Compose already starts it), and Windows `.bat` scripts.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `event-simulator`: adds the release command, equivalent to the Mix task.
- `demo-seeds`: adds the release command and its Docker-ready output.

## Impact

- New `CourierDemo.CLI` (argument parsing, summary, and the release entry points); `Mix.Tasks.Courier.Simulate` delegates to it; `CourierDemo.Seeds.report/2` takes the kind of commands to print.
- New `rel/overlays/bin/simulate` and `rel/overlays/bin/seed`, copied into the release by `mix release`.
- `README.md`, `docs/architecture.md`, `docs/roadmap.md`.
- No new dependencies, no database changes, no change to the courier application's supervision tree. Existing tests are not modified.
