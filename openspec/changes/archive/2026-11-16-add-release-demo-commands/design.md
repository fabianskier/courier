# Design

## Context

See proposal.md for the motivation. Today:

- `Mix.Tasks.Courier.Simulate` owns the option parsing, the validation messages and the summary; `CourierDemo.Simulator` (`plan/2`, `run/2`) is already free of Mix. `test/mix/tasks/courier_simulate_test.exs` is protected and asserts the task's messages through `Mix.shell()` and its `exit({:shutdown, 1})`.
- `CourierDemo.Seeds.report/1` prints `mix courier.simulate ...`, `mix ecto.reset` and `mix courier.demo.receiver`; `test/courier_demo/seeds_test.exs` is protected and asserts the first two.
- The release (`mix phx.gen.release --docker`) has `rel/overlays/bin/server` and `bin/migrate`. `bin/courier eval EXPR ARGS...` loads the configuration, starts no application and passes `ARGS` as `System.argv()`; `bin/courier rpc EXPR` evaluates in the running node and prints to the caller's terminal (checked by hand in step 7b).
- In Compose, the `courier` container already has the release environment, so `docker compose exec courier bin/<command>` needs no extra setup.

## Goals / Non-Goals

**Goals:** one parsing, validation and summary implementation for both entry points; release commands that are thin shell scripts over tested Elixir functions; no behaviour change for the Mix task or the Mix seeds.

**Non-Goals:** automatic seeding at start; configurable command names in the seed report; running the release scripts in the gate (it has no Docker).

## Decisions

**`CourierDemo.CLI` holds what both entry points share.**

- `parse_simulate(args, env \\ System.get_env())` returns `{:ok, config}` or `{:error, messages}`, with the option switches, defaults, validation and messages moved unchanged from the Mix task (the token default comes from `env["COURIER_INGEST_TOKEN"]`; option values are never echoed).
- `summary(tally)` returns the summary lines, moved unchanged.
- `simulate(args)` is the release entry point: on `{:ok, config}` it starts `:req`, runs `Simulator.plan/1` and `Simulator.run/2`, prints the summary with `IO.puts/1` and returns `0`; on `{:error, messages}` it prints them and a usage line (`Usage: bin/simulate --merchant ID [--merchant ID...] [options]`) to `:stderr` and returns `1`. It returns the status instead of halting so tests can call it.
- `seed()` is the release entry point for the seeds: `Seeds.run() |> Seeds.report(:release) |> IO.puts()`, returning `:ok`.

`Mix.Tasks.Courier.Simulate` keeps `Mix.Task.run("app.config")`, `Mix.shell()` and `exit({:shutdown, 1})`, and calls `CLI.parse_simulate/1` and `CLI.summary/1`. Alternative considered: making the Mix task call `CLI.simulate/1`; rejected because the protected test reads the output from `Mix.shell()`.

**`Seeds.report/2` takes the kind of commands: `:mix` (default) or `:release`.** `report/1` keeps today's text. With `:release` the simulate command is `docker compose exec courier bin/simulate --token ... --merchant ...`, the already-seeded hint is `docker compose down -v` followed by `docker compose up -d --build` and `docker compose exec courier bin/seed`, and the unreachable-receiver hint is `docker compose up -d demo-receiver` and seeding again from an empty database. Alternative considered: printing a bare `bin/simulate`, which a user would have to prefix by hand; rejected because the report promises a command that runs as printed, and the release's only supported home for these commands is the Compose demo.

**Release scripts are overlays, like `bin/server` and `bin/migrate`.**

```sh
# rel/overlays/bin/simulate
exec ./courier eval 'System.halt(CourierDemo.CLI.simulate(System.argv()))' "$@"

# rel/overlays/bin/seed
exec ./courier rpc 'CourierDemo.CLI.seed()'
```

Both start with `#!/bin/sh`, `set -eu` and the `cd` of the generated scripts, and are committed executable (`git update-index --chmod=+x`). The simulator uses `eval` because it needs no running application, only `:req`; the seeds use `rpc` because they need the repo, the vault and the contexts, which the running node already has. Alternative considered for the seeds: `eval` after `Application.ensure_all_started(:courier)`; rejected because it would start a second Oban and endpoint next to the server.

**Tests** go in new files and call the Elixir entry points, not the shell scripts: `test/courier_demo/cli_simulate_test.exs` (`async: false`; `Req.Test` stub of `CourierDemo.Simulator`, `ExUnit.CaptureIO` for both devices, the environment passed as an argument to `parse_simulate/2` or set with `System.put_env/2` and restored) and `test/courier_demo/cli_seed_test.exs` (`Courier.DataCase`, `Req.Test` stub of `CourierDemo.Seeds`, receiver URL `https://receiver.public.test` through `COURIER_DEMO_RECEIVER_URL` or by calling `Seeds.run/1` and `Seeds.report/2` as `seed/0` does).

## Risks / Trade-offs

- [The shell scripts are not covered by the gate] → They are one line each over tested functions; the workflow follow-up runs them in Docker after the merge.
- [`bin/seed` needs the release to be running] → That is how Compose runs it (`docker compose exec`); the README says so.
- [The seed report hard-codes the Compose service name `courier`] → It matches `compose.yaml`; documented next to it.
- [The demo token appears in the simulate command the seeds print] → Same as the Mix seeds: it is printed once, to the terminal that ran the command, and never logged.
