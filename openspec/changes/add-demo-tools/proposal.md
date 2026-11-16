# Proposal

## Why

The backend can already ingest, deliver, retry, dead-letter and resend, but showing it needs a hand-made receiver and a dozen `curl` calls. A reviewer should see retries, dead letters, resend and per-endpoint isolation in a few minutes with real signed requests (FR-40, FR-41), and the coming MCP server and dashboard need realistic data to work against.

## What Changes

- **Demo receiver**: a small HTTP server, separate from courier's own endpoint, that verifies Standard Webhooks signatures on its own (not with courier's signer) and answers by path: `/hooks/<name>/ok` (`200`), `/fail` (`500`), `/rate-limit` (`429` with `Retry-After`), `/bad-request` (`400`) and `/timeout` (answers after courier's deadline). Secrets are registered per name in memory through `PUT /_secrets/<name>`; a request for a name without a secret is answered unchecked. Started with `mix courier.demo.receiver` (loopback, port 4001 by default), or `CourierDemo.Receiver.serve/1` from a release.
- **Producer simulator**: `mix courier.simulate` posts events to `POST /api/v1/events` at a configurable rate and count, for one or more merchants and event types, and resends a configurable share of earlier requests unchanged with the same idempotency key; it prints how many were new (`202`), repeats (`200`), rejected and failed.
- **Demo seeds**: `priv/repo/seeds.exs` creates a `demo` API key (`ingest`, `read`, `write`), three merchants and five endpoints pointing at the receiver's paths (one per behaviour, one with an event-type filter so some deliveries are `skipped`, one with a short retry window so dead letters show up during a demo), registers each endpoint's secret with the receiver when it is reachable, and prints the token, the merchant ids and a ready `mix courier.simulate` command. It refuses to run twice on the same database.
- Docs: a "Demo tools" section in `docs/architecture.md`, a local demo walkthrough in the README, and the code layout updated (`lib/courier_demo/` instead of `demo/receiver/`).
- **Not in this change**: the Docker image (`mix release`), the `courier` and `demo-receiver` services in `compose.yaml`, and the reviewer's one-command demo. That scaffolding is generated (`mix phx.gen.release --docker`), so it becomes a manual bootstrap step (7b in the roadmap), like the other bootstraps.

## Capabilities

### New Capabilities
- `demo-receiver`: the receiver's signature check, its per-path behaviours and secret registration.
- `event-simulator`: the producer simulator's options, pacing, repeats and summary.
- `demo-seeds`: the demo data set, secret registration with the receiver and the refusal to seed twice.

### Modified Capabilities
None.

## Impact

- New `lib/courier_demo/` (`CourierDemo.Receiver`, `CourierDemo.Receiver.Secrets`, `CourierDemo.Simulator`, `CourierDemo.Seeds`), new Mix tasks `courier.demo.receiver` and `courier.simulate`, `priv/repo/seeds.exs`, config for the receiver and the seeds' HTTP client in `config/config.exs` and `config/test.exs`.
- Uses dependencies already in `mix.exs` (`bandit`, `plug`, `req`, `jason`); no new ones. No database changes. The domain contexts are used only through their public functions. Existing tests are not modified.
- The demo code is compiled into every environment (so a release can run the receiver) but nothing starts it unless asked: the courier application's supervision tree does not change.
