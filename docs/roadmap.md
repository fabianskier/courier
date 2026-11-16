# Roadmap

## Build path

Each step after the bootstraps is one OpenSpec change, built task by task with `mix smelt.task` and merged after human approval. Smelt's gate needs a `.smelt/checks.sh` in the base commit and limits each task to about 400 changed lines and 20 files, so generated scaffolding (Phoenix, Vite, shadcn) is done by hand in bootstrap commits, not through Smelt.

| # | Step | Kind | Covers |
|---|---|---|---|
| 0 | **Backend bootstrap**: `mise.toml` (Elixir 1.20.5 / OTP 29, as in Smelt), `mix phx.new . --app courier --no-html --no-assets --no-mailer --no-gettext --binary-id`, `DATABASE_URL`, Oban 2.24 with its migration and `testing: :manual`, `.smelt/checks.sh`, `.smelt/gate.json`, GitHub Actions CI, `compose.yaml` with Postgres. | manual | setup |
| 1 | `add-access-keys`: API keys (hashed), scopes `ingest`/`read`/`write`, auth plug, `mix courier.keys.create`. | change | FR-4 (auth), ADR API keys |
| 2 | `add-merchants-endpoints`: merchants, endpoints, event-type filters, URL safety (SSRF, allowlist), encrypted secrets with rotation, REST endpoints. | change | FR-6 to FR-9 |
| 3 | `add-event-ingestion`: `POST /api/v1/events`, idempotency (repeat and key reuse), fan-out to `pending`/`skipped` deliveries in one transaction, size limit. | change | FR-1 to FR-5, FR-10 |
| 4a | `add-webhook-delivery`: Standard Webhooks signer, Req client without retries, worker with backoff, jitter, `Retry-After` and retry window, append-only attempts (trigger), queue per endpoint (`QueueManager`), `GET /api/v1/deliveries/:id`. | change | FR-11 to FR-16, FR-18 to FR-20, FR-35 |
| 4b | `add-endpoint-health`: consecutive failures, `degraded` flag, slow-endpoint isolation test. | change | FR-17, FR-36 |
| 5 | `add-manual-resend`: resend API, links and actor, `409` for deliveries in progress. | change | FR-21 to FR-23 |
| 6 | `add-observability`: telemetry events, metrics, LiveDashboard behind the admin key. | change | FR-33, FR-34 |
| 7 | `add-demo-tools`: demo receiver (signature check, scripted failures), `mix courier.simulate`, full `compose.yaml`, seeds. | change | FR-40, FR-41 |
| 8 | `add-mcp-server`: `anubis_mcp` at `/mcp`, read tools, `resend_delivery` with `write` scope, call log. | change | FR-29 to FR-32 |
| 9 | **Frontend bootstrap**: Vite + React + TypeScript strict, TanStack Router and Query, Tailwind, `shadcn init`, build into `priv/static`, dev proxy, frontend checks added to `.smelt/checks.sh` and `.smelt/gate.json` test paths. | manual | setup |
| 10 | `add-dashboard-deliveries`: token entry, events and deliveries lists with filters, attempt timeline, failed view, resend. | change | FR-24 to FR-26 |
| 11 | `add-dashboard-endpoints`: merchants and endpoints management, secret shown once, degraded endpoints. | change | FR-27 |
| 12 | `add-dashboard-live-updates`: PubSub broadcasts, `DashboardChannel`, query invalidation, reconnect. | change | FR-28 |
| 13 | `add-retention`: daily pruning job and the trigger exception. | change | FR-37 to FR-39 |
| 14 | **Polish**: README with diagrams, demo GIF, load test script and measured numbers in `docs/analysis.md`. | change / manual | NFRs |

Steps 1 to 8 give a complete backend that can be demoed with `curl`, the demo receiver and Claude Code over MCP, before any frontend work.

## Current status

**Done:**
- Analysis, architecture and decisions (15 ADRs accepted, 2026-11).
- Repository: `git init`, `openspec init --tools claude` (project context in `openspec/config.yaml`), own skills synced from `agent-skills`, third-party skills `shadcn` and `mcp-builder` installed (reviewed; `mcp-builder`'s `evaluation.py` needs an API key and is not used).
- `CLAUDE.md`, `LICENSE` (all rights reserved), `README.md` and `docs/development.md` (how the project is built with Smelt; update its status section when Smelt gains features).

- Step 0, backend bootstrap: Phoenix 1.8.16 (`--no-html --no-assets --no-mailer --no-gettext --binary-id`), `DATABASE_URL` from `mise.toml` in dev, Oban 2.24 (Basic engine, no static queues, Pruner 7 days, Lifeline, migration v14, `testing: :manual`), `.smelt/checks.sh`, GitHub Actions CI (mise + Postgres 18 service, runs the gate checks), `compose.yaml` with Postgres 18. LiveDashboard at `/dev/dashboard` in dev only.

- Step 1, `add-access-keys`: `Courier.Access` with hashed API keys and scopes `ingest`/`read`/`write`, `mix courier.keys.create`/`list`/`revoke`, Bearer authentication and scope plugs, the `{"error": {"code", "message"}}` error shape and `GET /api/v1/me`. Documented in `docs/architecture.md` ("Authentication"); living spec `openspec/specs/api-access/spec.md` (archived 2026-11-15).

- Step 2, `add-merchants-endpoints`: `Courier.Merchants` and `Courier.Endpoints` with their REST API (`read`/`write` scopes), event-type filters, the URL policy (https, no credentials, public addresses only after DNS resolution, host allowlist), `whsec_` signing secrets encrypted at rest with Cloak (`COURIER_ENCRYPTION_KEY`) and rotation with a 24 h overlap, and keyset cursor pagination. `mix courier.keys.*` no longer print SQL. Documented in `docs/architecture.md` ("Merchants and endpoints").

- Step 3, `add-event-ingestion`: `Courier.Ingestion` with `POST /api/v1/events` (`ingest` scope, required `Idempotency-Key`, `202` for new events, `200` for repeats, `422 idempotency_key_reused` for a key reused with a different body, `422 merchant_disabled`, `413 payload_too_large` above 256 KB), the event and one `pending`/`skipped` delivery per enabled endpoint stored in one transaction with each pending delivery's retry window, and `GET /api/v1/events` (newest first, filters by merchant and type) and `GET /api/v1/events/:id` with the `read` scope. Shared `CourierWeb.LogCapture.capture_debug_log/1` test helper and a working test for the `api-access` scenario "Rejected token not echoed". Documented in `docs/architecture.md` ("Event ingestion").

- Step 4a, `add-webhook-delivery`: `Courier.Delivery.Signer` (Standard Webhooks, one `v1,` signature per active secret), `Courier.Delivery.Client` (Req, no retries or redirects, explicit timeouts, `Courier.Finch` pool of 50 per origin), `Courier.Delivery.RetryPolicy` (capped exponential backoff with full jitter, `Retry-After` on `429`/`503`, the retry window as the only stop rule), `Courier.Delivery.Worker` (URL policy re-checked before every request, Oban snooze for retries), append-only `attempts` protected by a trigger with the `courier.retention` exception, `Courier.Delivery.QueueManager` with one Oban queue `endpoint:<id>` per enabled endpoint, delivery jobs inserted in the ingestion transaction, a stable delivery order, a repeat answered as such after its merchant was disabled, and `GET /api/v1/deliveries/:id` with the `read` scope. Documented in `docs/architecture.md` ("Webhook delivery"); the DNS rebinding gap is noted in "Security notes".

**Next:**
1. Archive `add-webhook-delivery` and check it end to end against a local receiver (signature verified, a `503` retried, a `400` failed).
2. Propose OpenSpec change `add-endpoint-health` (step 4b, FR-17, FR-36): consecutive failure count, `degraded` flag and the isolation test with a slow endpoint. Also decide what happens to the pending deliveries of an endpoint disabled for good.
