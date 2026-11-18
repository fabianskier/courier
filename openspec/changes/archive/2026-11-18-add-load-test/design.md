# Design

## Context

See proposal.md. What exists:

- `CourierDemo.Simulator`: `plan/2` builds `{idempotency_key, body}` requests for given merchants and types (with a share of repeats); `run/2` sends them with pacing (`i * 1000 / rate` ms), up to a fixed concurrency, no retries, and returns a tally (`:new`, `:repeats`, `:rejected` by status, `:failed`, `:elapsed_ms`). Its Req options can be routed to `Req.Test` through `config :courier, CourierDemo.Simulator, req_options:`.
- `CourierDemo.CLI`: `parse_simulate/2`, `simulate/1` (exit status), shared by `mix courier.simulate` and `rel/overlays/bin/simulate` (`bin/courier eval '...CLI.simulate(System.argv())'`). `eval` starts no application.
- `Courier.Release` starts the repo for migrations with `Ecto.Migrator.with_repo/2`.
- Tables: `deliveries (id, endpoint_id, status, inserted_at)`, `attempts (delivery_id, number, started_at)`, `endpoints (id, url)`; indexes on `deliveries (inserted_at, id)` and `attempts (delivery_id, number)`.

## Goals / Non-Goals

**Goals:** one command that produces the four numbers in the NFR table; pure, tested statistics; measurements from the database so they include queueing, not only HTTP.

**Non-Goals:** a load generator that outruns one Elixir VM, latency histograms, comparing runs over time.

## Decisions

**Sending.** `Simulator.run/2` gains `latencies: true`: each request is timed with `System.monotonic_time/1` around `Req.post/3`, and the tally gains `:latencies_ms` (a list). Without the option nothing changes. The load command builds its plan with `repeat_share: 0.0` so every event is new and creates deliveries.

**Window.** The command records `started_at = DateTime.utc_now()` before the first request and `finished_at` after the last. The run's deliveries are those of the given merchants' events with `inserted_at` in `[started_at, finished_at]` and status other than `skipped`.

**Waiting.** Every second, up to `--wait`, it counts the run's deliveries without an attempt number 1; it stops early at zero.

**Delivery query.** One query joins the run's deliveries to their attempt number 1 and their endpoint: `{endpoint_url, delivery.inserted_at, attempt.started_at or nil}`. Attempts per second: count of attempts with `started_at` in `[started_at, now]` divided by that interval in seconds.

**Statistics.** `CourierDemo.Load.Stats.percentile(values, p)` uses nearest-rank on the sorted list (`ceil(p/100 * n)`-th value), which gives p50 = 50, p95 = 95, p99 = 99 for 1..100. Empty lists report `n/a`.

**Database access from the release.** `bin/load` runs `bin/courier eval 'System.halt(CourierDemo.CLI.load(System.argv()))'`. `CLI.load/1` starts `:req`, then runs the delivery part inside `Ecto.Migrator.with_repo(Courier.Repo, fn _ -> ... end, pool_size: 2)`, so it does not start Oban, the endpoint or the delivery workers next to the running server. `mix courier.load` uses `Mix.Task.run("app.config")` and the same `with_repo` call.

**Report.** Plain text, one block per part, for example:

```text
Ingestion: 1500 sent in 30.0 s (50.0/s): 1500 x 202, 0 failed
  latency p50 4 ms, p95 9 ms, p99 15 ms
Delivery: 3000 deliveries, 0 without an attempt after 30 s
  time to first attempt p50 120 ms, p95 480 ms
  attempts 102.3/s
  http://demo-receiver:4001/hooks/sunrise-ok/ok   1500  p50 110 ms  p95 300 ms
  ...
```

**Tests.** `test/courier_demo/load_stats_test.exs` (percentiles), `test/courier_demo/load_test.exs` (option parsing, ingestion report from a stubbed run with `Req.Test`, delivery report from rows inserted with fixtures and explicit timestamps, the per-endpoint lines, deliveries without attempts). The release scenario is checked by a test that the overlay script exists, is executable and calls `CourierDemo.CLI.load`, and by the manual Docker run.

## Risks / Trade-offs

- [The client runs inside the same container as the server] → client and server share CPU; the README states the numbers are for a single laptop, as the NFR table says.
- [Clock differences] → none: both timestamps come from the same database server (`inserted_at` and `started_at` are set by courier on the same host).
- [Other traffic during the run] → the window and merchant filter limit it; the README tells to run it on an idle demo.
