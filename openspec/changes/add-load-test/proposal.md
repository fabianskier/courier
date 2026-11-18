# Proposal

## Why

The non-functional targets in `docs/analysis.md` (ingestion latency, ingestion throughput, time to first attempt, delivery throughput) say they are "measured by a load script included in the repo", and two of them are still "TBD after first measurement". The project has a simulator that sends events at a rate, but nothing measures latency or delivery timing, so none of the numbers can be checked. This is the last roadmap step (14) together with the README polish.

## What Changes

- **Load command**: `mix courier.load` and the release command `bin/load` send events at a given rate and count (reusing the simulator's plan and pacing), then report:
  - ingestion: requests sent, achieved rate, statuses, and client latency p50/p95/p99;
  - delivery: for the deliveries created during the run, time to first attempt p50/p95 overall and per endpoint (so a slow endpoint's isolation shows), and attempts per second during the run.
  It waits up to a timeout for the run's deliveries to get their first attempt, and says how many did not.
- **Simulator**: an internal option to record each request's latency, used by the load command; `bin/simulate` behaves as before.
- **README polish**: diagrams (containers and the delivery lifecycle) near the top, a short "Measured performance" section pointing at `docs/analysis.md`, and a check of every walkthrough step against the current commands.
- **Measured numbers**: after the tasks, the targets in `docs/analysis.md` get the measured values from the Docker demo on the author's laptop (a manual step, not a task).
- **Not in this change**: a demo GIF (recorded by hand), CI load runs, and distributed load generation.

## Capabilities

### New Capabilities
- `load-test`: the load command, what it measures and how it reports.

### Modified Capabilities
None. The simulator gains an internal option the load command uses; its specified behaviour does not change.

## Impact

- New `lib/courier_demo/load.ex` (and a report module if it grows), `lib/mix/tasks/courier.load.ex`, `rel/overlays/bin/load`; `CourierDemo.Simulator.run/2` gains a `:latencies` option; `CourierDemo.CLI` gains `load/1`.
- The release command reads the database through `Courier.Repo` started on its own (not the whole application), like the migrate command does.
- README and `docs/analysis.md` updated. No schema changes; existing tests are not modified.
