# Decisions

Each decision records its context, the options considered, what was chosen and its consequences. Decisions start as `proposed`; the author marks them `accepted`. When a decision changes, mark it `superseded by …` instead of deleting it.

Requirement ids (FR-n) refer to [analysis.md](analysis.md).

## One Phoenix application with domain contexts

**Status:** accepted (2026-11)
**Context:** One developer, a local demo, and agent-built tasks that must stay small. Ingestion, delivery, the dashboard API and MCP all work on the same data.
**Options considered:**
- *One Phoenix app, contexts under `lib/courier/`*: one release and one test suite; boundaries are enforced by convention and review.
- *Umbrella app (core, web, mcp)*: compile-time boundaries, but more config and tooling friction for agents and for readers.
- *Separate services (ingestion, delivery)*: independent scaling, but needs a broker or shared DB, distributed tracing and more ops, none of which a single-node demo needs.
**Decision:** A single Phoenix application. Domain logic lives in contexts; the JSON API, the MCP adapter and the workers call the same context functions.
**Consequences:** Simple to run, test and read. Boundaries depend on discipline (reviews, and possibly a `boundary` check later). Splitting a service out later means extracting a context, which the layout keeps possible.

## PostgreSQL as the only data store

**Status:** accepted (2026-11)
**Context:** Idempotency needs a unique constraint (FR-2); durability needs the event and its jobs written together (FR-5); the audit trail needs append-only rows and queries (FR-18 to FR-20).
**Options considered:**
- *PostgreSQL*: transactions, unique constraints, JSONB payloads, triggers for append-only tables; Oban runs on it.
- *PostgreSQL + Redis*: faster queues and rate limits, but two stores and no shared transaction between event and job.
- *SQLite*: zero setup, but weaker concurrency for workers and fewer Oban features.
**Decision:** PostgreSQL only, configured through `DATABASE_URL`.
**Consequences:** One transaction covers event, deliveries and jobs, so no outbox is needed. Queue throughput is bounded by Postgres, which is far above the demo targets. Docker or a local Postgres is required.

## Oban with one queue per endpoint schedules deliveries and is the only layer that retries

**Status:** accepted (2026-11)
**Context:** Retries need exponential backoff with jitter, `Retry-After` support and a 24 h window (FR-13 to FR-15). They must survive restarts and be visible. Retrying in two layers multiplies attempts and breaks the audit trail. Deliveries must run concurrently, and each endpoint must be isolated (a bulkhead): a slow or dead endpoint may use only its own share of concurrency, never stall other merchants (FR-35, FR-36). Jobs must be inserted in the same transaction as the event (FR-5). Oban Pro (partitioned or global limits) is not an option.
**Options considered:**
- *One shared Oban queue*: simplest, but a slow endpoint can take every slot of the queue; open-source Oban has no per-key (partitioned) limits.
- *One shared Oban queue + in-process per-endpoint semaphore (busy jobs snooze)*: keeps one queue, but busy jobs are fetched and snoozed again and again (wasted writes, no fairness), and the semaphore lives outside Oban's view.
- *One Oban queue per endpoint, started at runtime with `Oban.start_queue/2` (open-source)*: each endpoint gets its own producer and concurrency limit; jobs are still plain rows inserted in the event transaction; pausing an endpoint is `Oban.pause_queue/2`. Costs one producer process per active endpoint and a small manager that starts queues at boot and when endpoints change.
- *Own dispatcher: deliveries table as the queue, one GenServer per active endpoint (Registry + DynamicSupervisor) leasing due rows with `FOR UPDATE SKIP LOCKED` and running up to N `Task`s*: maximum control and scales to many idle endpoints, but we own leases, crash recovery, wake-up (LISTEN/NOTIFY) and telemetry that Oban already provides.
- *Broadway with an external queue (SQS, RabbitMQ)*: good for high volume, but adds a broker (out of scope) and loses the shared transaction.
**Decision:** One Oban queue per endpoint (`endpoint:<id>`) with a configurable limit (`max_concurrency`, default 10). `Courier.Delivery.QueueManager` starts the queues of enabled endpoints at boot and starts, scales or stops them when endpoints are created, updated or disabled. Each delivery is one job in its endpoint's queue, inserted in the ingestion transaction. The worker computes the next run time (backoff with jitter or `Retry-After`) and snoozes the job; in Oban 2.24 a snooze does not consume an attempt, and the delivery's retry window, not `max_attempts`, decides when to stop. Req runs with `retry: false`, explicit timeouts and a connection pool per endpoint origin at least as large as the queue limit.
**Consequences:**
- Isolation per endpoint: a dead endpoint holds at most `max_concurrency` processes; total concurrency is the sum across endpoints, which the BEAM handles easily (deliveries are I/O-bound).
- Transactions, durability, retries and telemetry stay Oban's; we add only the queue manager.
- Pausing a degraded endpoint becomes cheap (`pause_queue`), which answers an open question if the author wants it.
- Queue limits are per node: with several nodes the real limit is nodes × `max_concurrency` (fine for a single-node v1; a global limit would need a DB-backed counter or Pro).
- One producer per endpoint queue fits hundreds to low thousands of endpoints. If that ever stops scaling, this ADR is superseded by the own-dispatcher option, which keeps the same tables.
- Tests must cover: queue started on endpoint creation, stopped on disable, and a slow endpoint not delaying another endpoint's deliveries.

## Deliveries with append-only attempts; resend creates a new delivery

**Status:** accepted (2026-11)
**Context:** Support must answer "did the merchant get it, and when?" from stored data (FR-20), and a resend must never rewrite history (FR-22).
**Options considered:**
- *Event → delivery per endpoint → append-only attempts; resend = new delivery linked to the original*: clear history, simple queries, each delivery has one lifecycle.
- *Mutable status and retry counter on the event*: fewer tables, but loses per-endpoint and per-attempt history.
- *Full event sourcing of delivery state*: perfect history, but complex projections for a small domain.
**Decision:** The first option. Attempts are insert-only, protected by a database trigger. Deliveries move only forward from `pending` to a terminal state. Filtered-out endpoints get a `skipped` delivery.
**Consequences:** Timelines and audit queries are direct. Resend chains need a recursive or repeated lookup in the UI. The trigger means retention (if added) needs a privileged migration-level job.

## Sign webhooks with the Standard Webhooks scheme

**Status:** accepted (2026-11)
**Context:** Receivers must verify authenticity and reject replays (FR-11), and secrets must rotate with an overlap (FR-7). A public project benefits from a scheme receivers already know.
**Options considered:**
- *Standard Webhooks*: headers `webhook-id`, `webhook-timestamp`, `webhook-signature` (`v1,<base64 HMAC-SHA256 of "id.timestamp.body">`), several signatures for rotation, existing verification libraries in many languages.
- *Custom Stripe-style header* (`Courier-Signature: t=…,v1=…`, signing `"timestamp.body"`): familiar and simple, but receivers must write their own verification.
- *Asymmetric signatures (Ed25519)*: no shared secret, but more key management and less common.
**Decision:** Standard Webhooks with HMAC-SHA256. `webhook-id` is the event id (stable across retries and resends); `courier-delivery-id` identifies the delivery.
**Consequences:** Receivers can use off-the-shelf libraries; the demo receiver verifies with the same scheme. Rotation sends two signatures during the overlap. The `whsec_` secret format and base64 encoding must match the spec exactly, checked with test vectors from the spec.

## Event-type filters per endpoint

**Status:** accepted (2026-11)
**Context:** Merchants choose which events an endpoint receives (FR-9). The author chose event-type filtering for v1.
**Options considered:**
- *Event-type patterns (exact or `prefix.*`)*: easy to explain, validate and test; matches common providers.
- *Conditions on payload fields*: more flexible, but needs an expression language, validation and security review.
- *Payload projection per merchant*: changes what is signed and stored; hard to audit.
**Decision:** A list of event-type patterns per endpoint; empty means all. Matching happens at ingestion; non-matching endpoints get a `skipped` delivery.
**Consequences:** Simple and fully testable. Changing filters affects only future events. Payload conditions can be added later as a new ADR.

## API keys with scopes for producers, operators and agents

**Status:** accepted (2026-11)
**Context:** External auth providers are out of scope, but ingestion, the dashboard and MCP must still be protected, and resend must need more rights than reading (FR-4, FR-21, FR-30).
**Options considered:**
- *API keys stored as hashes with scopes `ingest`, `read`, `write`*: one mechanism for the producer, the dashboard and MCP; keys can be named, revoked and audited (`triggered_by`).
- *Static tokens in environment variables*: no table, but no revocation, no names in the audit trail.
- *User accounts (`phx.gen.auth`)*: real logins, but out of scope and heavier for a demo.
**Decision:** API keys in the database, random tokens stored as SHA-256 hashes, created by a mix task (and by seeds). The SPA asks for a token once and keeps it in session storage.
**Consequences:** Same auth for every client; resend records which key triggered it. A key in browser storage is acceptable for a local demo, not for production; real user auth would be a new ADR.

## Encrypt endpoint secrets at rest

**Status:** accepted (2026-11)
**Context:** Signing secrets must be readable to sign requests, so they cannot be hashed. A database dump with plaintext secrets would allow forged webhooks.
**Options considered:**
- *Plaintext column*: simplest, weakest.
- *Application-level encryption with Cloak.Ecto (AES-GCM), key from the environment*: proven library, transparent to queries; key rotation supported.
- *External KMS (AWS KMS, Vault)*: best practice in production, but needs cloud resources the local demo does not have.
**Decision:** Cloak.Ecto with a key from `COURIER_ENCRYPTION_KEY`; development and test use a fixed non-secret key.
**Consequences:** Small extra dependency and config. A KMS-backed key can replace the environment key later without changing the schema.

## Monorepo with the SPA served by Phoenix

**Status:** accepted (2026-11)
**Context:** The dashboard is React + shadcn/ui (brief). Reviewers should clone one repo and run one command; agents work in one worktree per task.
**Options considered:**
- *Monorepo: `frontend/` built by Vite into `priv/static`, served by Phoenix on the same origin*: one clone, one CI, no CORS; Phoenix and Node toolchains side by side.
- *Separate frontend repo and deployment*: independent releases, but CORS, two CIs and harder review.
- *React inside Phoenix's asset pipeline (esbuild)*: one toolchain, but fights shadcn's Vite-based setup and the official shadcn skill.
**Decision:** Monorepo. Vite builds into `priv/static`; in development the Vite dev server proxies `/api` and `/socket` to Phoenix.
**Consequences:** CI runs both Elixir and Node checks. Phoenix's default esbuild/tailwind assets are not used for the dashboard. Smelt tasks may touch either side; `.smelt/checks.sh` must run both test suites.

## Vite and TanStack Router for the dashboard

**Status:** accepted (2026-11)
**Context:** A client-rendered dashboard behind a token, with typed data access through TanStack Query; no SEO or server rendering needed.
**Options considered:**
- *Vite + TanStack Router*: type-safe routes and search params (useful for list filters), integrates with TanStack Query loaders.
- *Vite + React Router*: most widely known, fewer type guarantees on search params.
- *Next.js*: server rendering and its own server, which conflicts with Phoenix serving the app and adds a Node runtime.
**Decision:** Vite + TanStack Router, React + TypeScript strict, Tailwind and shadcn/ui.
**Consequences:** Typed URLs for filters and pagination. Slightly less familiar than React Router to some readers; the README explains the structure.

## Phoenix Channels push change notices; the dashboard refetches over REST

**Status:** accepted (2026-11)
**Context:** The dashboard must refresh within 5 s without a manual reload (FR-28). REST stays the only data API, because ingestion must be REST (`Idempotency-Key`) and the MCP adapter uses the same contexts. The author asked whether GraphQL subscriptions would fit.
**Options considered:**
- *Polling with TanStack Query (`refetchInterval` 2–5 s)*: no extra server code, but constant requests and up to one interval of delay.
- *Phoenix Channels carrying change notices; the client invalidates TanStack Query caches and refetches over REST*: real push from PubSub, one data API, small messages; needs socket auth and a topic design.
- *GraphQL (Absinthe) with subscriptions over Channels*: typed schema and push, but a second API next to REST ingestion, resolvers and dataloaders for a few fixed views, and a less maintained JS socket client.
- *Server-Sent Events*: push over plain HTTP, but long-lived connections, reconnect logic and a separate auth path, without the BEAM tooling Channels give.
**Decision:** Contexts broadcast domain changes over Phoenix PubSub; a `DashboardChannel` (topics such as `deliveries`, `endpoints`) forwards small notices (`delivery_changed` with id and status, `event_ingested`, `endpoint_changed`). The SPA joins with the same API key (`read` scope) and calls `queryClient.invalidateQueries` for the affected keys; data always comes from the REST API.
**Consequences:**
- One data API; push without duplicating data in socket messages.
- Socket authentication and topic authorization must be tested; notices carry ids and statuses only, never payloads.
- Bursts (many deliveries changing at once) must be coalesced on the client or server so the SPA does not refetch hundreds of times per second.
- On reconnect the SPA invalidates all active queries, so missed notices are harmless.

## MCP server with anubis_mcp over Streamable HTTP, inside the Phoenix app

**Status:** accepted (2026-11)
**Context:** Agents (Claude Code, Claude Desktop) must query courier and, with rights, resend (FR-29 to FR-32). The MCP layer must stay a thin adapter over contexts. Elixir MCP libraries are young.
**Options considered:**
- *`anubis_mcp` (2.x, the maintained fork of `hermes_mcp`), Streamable HTTP mounted at `/mcp`*: server support with Phoenix/Plug integration and current spec versions; one more dependency that still changes quickly.
- *Hand-written JSON-RPC handler for the tools subset*: no dependency, but we own protocol details (initialization, capabilities, versions) and their tests.
- *Separate stdio process (escript or release command)*: simple for Claude Desktop, but a second entry point that needs DB access and duplicated config; no reuse of API key auth.
- *`hermes_mcp`*: superseded by `anubis_mcp`.
**Decision:** `anubis_mcp` with Streamable HTTP inside the same release, authenticated with the same API keys (`read` or `write`) through the `Authorization` header.
**Consequences:** One process and one auth model; Claude Code connects with `claude mcp add --transport http`. Library versions are pinned and checked at the start of the MCP change; if the library is a poor fit then, this ADR is superseded by the hand-written option.

## Docker Compose for the local demo

**Status:** accepted (2026-11)
**Context:** The project runs locally only (author's choice). Reviewers should get a working demo in under 5 minutes without installing Elixir.
**Options considered:**
- *Docker Compose (`courier`, `postgres`, `demo-receiver`) plus seeds and a producer simulator*: one command, reproducible.
- *Local toolchain only (mise + Postgres)*: matches development, but reviewers must install Erlang, Elixir and Node.
- *Public hosting (Fly.io or similar)*: easiest to view, but costs money and exposes an attack surface; out of scope for v1.
**Decision:** Docker Compose for reviewers; mise + local Postgres for development (as in Smelt).
**Consequences:** A production-like release (`mix release`) is built in the Docker image. The demo receiver runs on a private network, so the SSRF allowlist (FR-8) is set in demo config only.

## Proprietary license: all rights reserved

**Status:** accepted (2026-11)
**Context:** Public portfolio repo. The author wants to keep full control of the project; it is meant to be read, not reused. The author holds the copyright under any option; the license only sets what others may do.
**Options considered:**
- *MIT*: permissive; anyone may reuse the code, even commercially, keeping the notice.
- *Apache-2.0*: permissive with a patent grant.
- *PolyForm Noncommercial*: source-available; non-commercial use only.
- *All rights reserved*: anyone can read the code on GitHub, but nobody may copy, modify or reuse it without permission.
**Decision:** All rights reserved. A `LICENSE` file says `Copyright (c) 2026 Oscar Fabián Cristaldo Guzmán. All rights reserved.` and the README says the code is published for review only.
**Consequences:** Full control for the author. GitHub's terms still let users view and fork the repository on GitHub. Outside contributions are not expected; if that changes, a new ADR picks an open license. Dependencies (MIT, Apache-2.0) remain compatible with private use.

## Retention: prune by age, with a controlled exception to append-only

**Status:** accepted (2026-11)
**Context:** Data is pruned after a configurable number of days, default 30 (FR-37 to FR-39). Attempts are append-only and protected by a database trigger (see "Deliveries with append-only attempts"), so deletion needs a deliberate, auditable exception. It should be the simplest thing that is safe to start with.
**Options considered:**
- *Trigger allows `DELETE` only when the transaction sets `courier.retention = on` (`SET LOCAL`)*: one job, plain SQL, a few lines of trigger code; the exception is explicit and testable, and any other delete still fails.
- *Separate database role that owns deletion (trigger checks `current_user`)*: stronger separation, but two roles and two connection pools for a local demo.
- *Monthly partitions dropped when old*: fast, no row deletes, but partitioning complicates migrations and unique constraints, and only fits month-based retention.
- *No retention in v1*: simplest, but leaves the requirement unmet and the demo database growing.
**Decision:**
- A daily Oban cron job (open-source `Oban.Plugins.Cron`) deletes an event, its deliveries and their attempts when **every** delivery of the event is terminal and the event's **last activity** (its insertion or the latest delivery completion, so a recent resend keeps an old event) is older than the retention period.
- The period is `COURIER_RETENTION_DAYS`, default 30, minimum 2 (longer than the 24 h retry window); invalid values fail at boot.
- Deletion runs in batches (for example 1,000 events per transaction); each transaction runs `SET LOCAL courier.retention = on`. `UPDATE` on attempts stays forbidden always.
- The job emits telemetry with the number of rows deleted.
**Consequences:** Retention without weakening append-only for normal code; short locks thanks to batching. Pruned idempotency keys become reusable (FR-39). Tests cover: the default of 30 days, a configured value, the minimum, events with pending or recently resent deliveries kept, and a delete outside the job rejected by the trigger. This refines the "privileged job" consequence of the delivery model ADR. Retention is one of the last changes to build; nothing before it depends on it.
