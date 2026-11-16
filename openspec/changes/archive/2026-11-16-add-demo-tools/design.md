# Design

## Context

See proposal.md for why. Facts that shape the approach:

- `.smelt/checks.sh` compiles and tests only the root Mix project, and every scenario needs an ExUnit test that the gate runs.
- Courier's client has a 15 s receive timeout and a 30 s total deadline per request (`Courier.Delivery.Client`); a receiver that answers after 35 s is a timeout from courier's side.
- A signing secret is returned only when an endpoint is created or rotated. Courier never stores it in plaintext and never logs it.
- The URL policy allows `http` and `localhost`, `127.0.0.1` and `demo-receiver` in development only; tests require `https` and resolve hosts by naming convention (`Courier.Endpoints.TestResolver`).
- `mix run priv/repo/seeds.exs` (and `mix ecto.setup`/`ecto.reset`) start the whole courier application, but not its HTTP endpoint.
- `test/courier/delivery/endpoint_isolation_test.exs` already runs real HTTP servers on loopback with `Client` and `URLPolicy` config overridden; the end-to-end receiver test follows that pattern.

## Goals / Non-Goals

**Goals:** demo tools covered by the same gate as the rest of the code; a receiver that checks courier's signatures with its own code, so it is an independent proof of the signer; seeds and simulator that use only public context functions or the public API.

**Non-Goals:** Docker image and Compose services (manual bootstrap 7b); persistence of receiver secrets; secret rotation in the receiver beyond accepting several `v1,` entries; load-test reporting (step 14 builds on the simulator).

## Decisions

### Code lives in `lib/courier_demo/`, inside the courier project

`CourierDemo.*` modules sit next to `lib/courier/`, `lib/courier_web/` and the future `lib/courier_mcp/`, and are compiled in every environment.

- *Alternative: a separate Mix project in `demo/receiver/`* (as sketched in `docs/architecture.md`). Its tests would sit outside the gate unless `.smelt/checks.sh` grows a second project, and it would need its own deps and formatter. Rejected for now; `docs/architecture.md` "Code layout" is updated.
- Compiling the code in `prod` lets a release run the receiver with `bin/courier eval "CourierDemo.Receiver.serve()"`, which the Compose bootstrap will use. The courier application's supervision tree does not change: nothing demo-related starts unless a task or `serve/1` asks for it.

### Receiver: a Plug served by Bandit in its own OS process

`CourierDemo.Receiver` is a `Plug.Router`; `CourierDemo.Receiver.Secrets` is an `Agent` (name → secret). `CourierDemo.Receiver.child_spec/1` returns a supervisor spec with the `Secrets` agent and `{Bandit, plug: {CourierDemo.Receiver, opts}, ip: ip, port: port}`. `serve/1` starts it and sleeps forever; `mix courier.demo.receiver [--port 4001] [--ip 127.0.0.1]` calls `serve/1` without starting the courier application (it needs no database).

- *Alternative: a child of `Courier.Application` in dev.* `mix run priv/repo/seeds.exs` starts the application too, so seeding while `mix phx.server` runs would try to bind port 4001 twice. Rejected.
- Options: `:timeout_delay_ms` (default 35 000, `COURIER_DEMO_TIMEOUT_MS`), `:retry_after` (30), `:tolerance_seconds` (300), `:secrets` (the agent's name, so tests can run several receivers). Tests start it with `start_supervised!/1` on port 0 and read the bound port with `ThousandIsland.listener_info/1`, as the isolation test does.
- Routes: `PUT /_secrets/:name`, `POST /hooks/:name/:behaviour`, anything else `404`. `Plug.Parsers` is not used on `/hooks`: the raw body is read with `Plug.Conn.read_body/2` (bounded to 1 MB) because the signature covers the exact bytes. `/_secrets` decodes JSON itself.

### Signature check written independently of `Courier.Delivery.Signer`

The receiver splits `webhook-signature` on spaces, keeps the `v1,` entries, computes `Base.encode64(:crypto.mac(:hmac, :sha256, key, "#{id}.#{ts}.#{body}"))` with `key = Base.decode64!(secret without "whsec_")` and compares each entry with `Plug.Crypto.secure_compare/2`. The timestamp must parse as an integer within `:tolerance_seconds` of `System.system_time(:second)`. Missing headers count as an invalid signature.

- *Alternative: call `Courier.Delivery.Signer.sign/4`.* Shorter, but a bug in the signer would then also be in the check, and the end-to-end test would prove nothing. Rejected.
- The verification result goes into one `Logger.info` line: `demo-receiver name=... behaviour=... signature=valid|invalid|unchecked webhook-id=... courier-delivery-id=...`.

### Secrets reach the receiver through `PUT /_secrets/:name`, in memory only

Seeds register each endpoint's secret right after creating it. The receiver binds to loopback by default; inside Compose it will be reachable only on the private network.

- *Alternative: seeds write the secrets to a shared file.* Simpler to survive restarts, but it stores plaintext secrets on disk. Rejected.
- *Alternative: the receiver reads secrets from courier's database.* A real receiver cannot; it would hide signing bugs. Rejected.
- After a receiver restart, requests are answered `signature=unchecked` until secrets are registered again (`mix ecto.reset` reseeds). Accepted for a demo tool.

### Simulator: plan first, then send

`CourierDemo.Simulator.plan(opts, rand)` builds the list of requests (`{idempotency_key, body}`) before sending: request `i` is a repeat with probability `repeat_share` (never for `i == 0`), copying a random earlier *new* request; otherwise a new key (`sim-<run id>-<i>`) and a body `%{"type", "merchant_id", "payload" => %{"amount", "currency", "reference"}}`, encoded once with `Jason.encode!/1` so repeats are byte-identical. `run(plan, opts)` sends request `i` no earlier than `start + i * 1000 / rate` ms, through `Task.async_stream/3` (`max_concurrency: 20`, `ordered: false`, `timeout: :infinity`), and tallies statuses.

- Requests use `Req` with `retry: false`; options merge `config :courier, CourierDemo.Simulator, req_options: []` so tests use `plug: {Req.Test, CourierDemo.Simulator}`.
- `mix courier.simulate` parses options with `OptionParser` (`merchant: :keep`), validates, and calls `plan/2` and `run/2`; it does not start the courier application (it talks to the API like any producer). The summary prints counts only; the token is never printed.
- Default types: `payment.succeeded`, `payment.failed`, `refund.succeeded` (so the `payment.*` filter produces `skipped` deliveries).

### Seeds: a module called by `priv/repo/seeds.exs`

`CourierDemo.Seeds.run(opts)` returns `{:ok, summary}` or `{:error, :already_seeded}`; `seeds.exs` only calls it and prints. It uses `Courier.Access.create_key/1`, `Courier.Merchants.create_merchant/1` and `Courier.Endpoints.create_endpoint/1` (so queues start and URLs pass the policy). It creates the `demo` key first: if the key exists, or a concurrent run creates it first (its name is unique), it returns `{:error, :already_seeded}` before creating anything else. No transaction wraps the rest, because `create_endpoint/1` starts each endpoint's Oban queue, which a rollback would not undo; a failure halfway leaves partial demo data, fixed with `mix ecto.reset`. Secret registration follows with `Req` (`retry: false`, 2 s timeouts, `req_options` from `config :courier, CourierDemo.Seeds`).

| Merchant | Endpoint name | Behaviour | Settings |
|---|---|---|---|
| Sunrise Bakery | `sunrise-ok` | `ok` | `event_types: ["payment.*"]` |
| Harbor Outfitters | `harbor-fail` | `fail` | `retry_window_seconds: 300` |
| Harbor Outfitters | `harbor-rate-limit` | `rate-limit` | defaults |
| Pine Hardware | `pine-bad-request` | `bad-request` | defaults |
| Pine Hardware | `pine-timeout` | `timeout` | `max_concurrency: 2` |

The endpoint name is the receiver path segment and the secret's registration name; it is also used as the endpoint `description`. The receiver URL comes from `opts[:receiver_url]`, else `COURIER_DEMO_RECEIVER_URL`, else `http://localhost:4001`; tests pass `https://receiver.public.test`, which the test resolver treats as public.

## Risks / Trade-offs

- [The registration route accepts secrets from anyone who can reach it] → Loopback by default, private network in Compose, and it is a demo tool that holds only demo secrets. Documented in "Security notes".
- [Demo code ships in the release] → Small and inert unless started; keeps the Compose bootstrap to one image.
- [The simulator's pacing depends on the API keeping up] → Requests are scheduled, not chained, with up to 20 in flight; a slower API lowers the effective rate, which the summary's elapsed time shows.
- [`/timeout` holds a receiver connection for 35 s] → Only the `pine-timeout` endpoint uses it, with `max_concurrency: 2`, which is also what makes the isolation visible.

## Migration Plan

None. Seeds run on demand (`mix run priv/repo/seeds.exs`, or as part of `mix ecto.setup`/`ecto.reset`).
