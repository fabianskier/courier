# Analysis

## Problem and goals

Platforms that process payments must tell their merchants about events (a payment succeeded, a refund failed) by calling the merchant's HTTP endpoint. Merchant endpoints are slow, flaky or down, so a naive "send once" loses events, and a naive retry loop sends duplicates nobody can trace. Support teams then cannot answer the basic question: *did the merchant get this event, and when?*

`courier` is a webhook delivery engine that:

- accepts events once (idempotent ingestion),
- delivers them **at least once**, signed, with bounded retries,
- keeps an append-only audit trail of every attempt,
- lets an operator inspect and resend from a dashboard or through an AI agent (MCP).

It is a public portfolio project. Goals besides the product itself: show payments-grade engineering (idempotency, retries, auditability) and a spec-driven, agent-built workflow (OpenSpec + Smelt), with docs, tests and CI that a reviewer can follow in minutes.

## Actors

| Actor | What they do |
|---|---|
| Producer (the platform) | Sends events to the ingestion API with an `ingest` API key. There is one producer in v1. |
| Merchant receiver | An HTTPS endpoint owned by a merchant that receives signed webhooks. |
| Operator | Uses the dashboard to inspect deliveries, manage merchants and endpoints, and resend. |
| AI agent | Claude Code or Claude Desktop using the MCP server to query and, when allowed, resend. |

## Functional requirements

### Ingestion

- **FR-1** `POST /api/v1/events` accepts an event with `type`, `merchant_id`, `payload` (JSON object), optional `occurred_at`, and an `Idempotency-Key` header. It returns `202` with the event id.
- **FR-2** A repeat with the same idempotency key and the same body returns `200` with the original event; no new event or delivery is created.
- **FR-3** A repeat with the same key and a different body returns `422` (`idempotency_key_reused`) and changes nothing.
- **FR-4** Requests without a valid `ingest` key get `401`; invalid bodies get `422` with field errors; bodies over the size limit get `413`.
- **FR-5** The event, its deliveries and their jobs are stored in one transaction: an accepted event is never lost, even if the process crashes right after the response.

### Merchants and endpoints

- **FR-6** An operator can create, list, update and disable merchants and their endpoints (URL, description, event-type filters, enabled flag).
- **FR-7** Creating an endpoint generates a signing secret, shown once. The secret can be rotated; during an overlap window (default 24 h) both secrets sign.
- **FR-8** Endpoint URLs must be `https` outside development and must not resolve to private, loopback or link-local addresses, except hosts on an explicit allowlist (used by the local demo receiver).
- **FR-9** Each endpoint has a list of event-type patterns: exact (`payment.succeeded`) or prefix wildcard (`payment.*`). An empty list means all types.

### Delivery

- **FR-10** For each accepted event, one delivery is created per enabled endpoint of the merchant. If an endpoint's filters exclude the event, its delivery is recorded as `skipped`, not omitted.
- **FR-11** Each request is a `POST` of the event JSON, signed following the Standard Webhooks scheme (see ADR), with a `courier-delivery-id` header.
- **FR-12** A `2xx` response marks the delivery `succeeded`.
- **FR-13** Network errors, timeouts, `408`, `429` and `5xx` are retried. Other `4xx` are not retried by default (configurable per endpoint).
- **FR-14** Retries use exponential backoff with jitter, capped, and honour `Retry-After` on `429` and `503`.
- **FR-15** Retries stop at the end of the retry window (default 24 h, configurable per endpoint, maximum 24 h). The delivery then becomes `failed` (dead-letter) and stays visible.
- **FR-16** Redirects are not followed; a `3xx` counts as a non-retryable failure.
- **FR-17** After N consecutive failed attempts (default 20, TBD) an endpoint is marked `degraded` and a telemetry event is emitted. A success clears the flag. Deliveries keep retrying within their window; the endpoint is not paused.
- **FR-35** Deliveries run concurrently. Each endpoint has its own concurrency limit (`max_concurrency`, default 10, configurable per endpoint).
- **FR-36** A slow or failing endpoint never delays deliveries to other endpoints: with one endpoint timing out on every request, the time to first attempt for the others stays within the NFR target.

### Audit trail

- **FR-18** Every attempt is stored as an append-only row: delivery, attempt number, start time, duration, request summary (URL, redacted headers), response status, truncated response body, error.
- **FR-19** Rows in the attempts table are never updated, and are deleted only by the retention job (FR-37).
- **FR-20** From the delivery and attempt tables alone, an operator can tell whether and when a merchant received an event.

### Manual resend

- **FR-21** An operator or agent with `write` scope can resend a delivery in a terminal state (`succeeded`, `failed`, `skipped`). Resending a delivery that is still in progress returns `409`.
- **FR-22** A resend creates a new delivery linked to the original (`resend_of_id`), with the actor recorded. The original delivery and its attempts are never changed.
- **FR-23** A resend sends the same event id in `webhook-id`, so receivers that de-duplicate keep working.

### Dashboard

- **FR-24** Lists events and deliveries with filters (status, merchant, endpoint, event type, time range) and cursor pagination.
- **FR-25** Shows a delivery's attempt timeline, including status codes, durations, errors and links to resends.
- **FR-26** Has a "failed deliveries" view and a resend action with confirmation.
- **FR-27** Manages merchants and endpoints (FR-6, FR-7, FR-9), and shows degraded endpoints.
- **FR-28** Data refreshes without a manual reload, within 5 s of a change.

### MCP server

- **FR-29** Read-only tools: `get_event`, `get_delivery` (with attempts), `list_deliveries` (filters, limit, cursor), `list_failed_deliveries`, `get_endpoint_health`.
- **FR-30** One mutating tool, `resend_delivery`, available only with a `write`-scoped token. Its description says it changes state.
- **FR-31** Tool output is compact and structured; payloads and response bodies are truncated and marked as untrusted data.
- **FR-32** Every tool call is logged (tool, key name, arguments without secrets, result status).

### Observability

- **FR-33** Telemetry events for: event ingested, attempt started/finished (with outcome and duration), delivery succeeded/failed, retry scheduled, endpoint degraded, queue lag.
- **FR-34** Phoenix LiveDashboard with custom metrics for the above, behind the admin token.

### Retention

- **FR-37** A daily job deletes events whose last activity (insertion or latest delivery completion) is older than the retention period, together with their deliveries and attempts. The period is configured in days (`COURIER_RETENTION_DAYS`); if it is not set, it is 30 days. The minimum is 2 days, longer than the retry window.
- **FR-38** The retention job never deletes an event that still has a `pending` delivery, and it reports how many rows it deleted (telemetry and log).
- **FR-39** After an event is pruned, its idempotency key is free again: a repeat with that key creates a new event. The README states this.

### Demo tools

- **FR-40** A producer simulator (`mix courier.simulate`) sends events at a configurable rate, with a share of repeated idempotency keys.
- **FR-41** A demo receiver verifies Standard Webhooks signatures and can be told, per path, to answer `200`, `500`, `429` with `Retry-After`, `400`, or time out, so retries, dead letters, resend and per-endpoint isolation are visible in a short demo.

## Non-functional requirements

Targets are for a single node on a developer laptop (local demo), measured by a load script included in the repo.

| Area | Target |
|---|---|
| Ingestion latency | p95 < 50 ms at 50 events/s |
| Ingestion throughput | ≥ 200 events/s sustained on one node (TBD after first measurement) |
| Time to first attempt | p95 < 2 s after ingestion when the queue is not backlogged |
| Delivery throughput | ≥ 100 attempts/s with a fast receiver (TBD) |
| Request timeouts | connect 5 s, receive 10 s (configurable) |
| Payload size | max 256 KB per event |
| Stored response body | first 4 KB |
| Backoff | base 10 s, factor 2, cap 1 h, with jitter → roughly 30–50 attempts in a 24 h window |
| Retention | configurable in days, default 30 (FR-37) |
| Delivery guarantee | at least once; no ordering guarantee |
| Durability | no accepted event lost on crash or restart (FR-5) |
| Availability | not a target: local demo, single node |
| Quality | every OpenSpec scenario has an ExUnit test; `mix precommit` and frontend checks pass in CI |
| Setup | `docker compose up` gives a working demo with seed data in < 5 min on a clean machine |

## Constraints

- One developer; agents build tasks through Smelt with a Claude Pro quota, so tasks must be small and specs precise.
- No Anthropic API key anywhere. Claude is used only through Claude Code; the "assistant" is the MCP server used by Claude Code or Claude Desktop.
- Public repository: original code only, no employer code, data, names or payload formats.
- Stack proposed in the brief: Elixir (1.20 / OTP 29, as in Smelt), Phoenix, Ecto, PostgreSQL, Oban (open-source edition, no Oban Pro), Req, React + TypeScript + shadcn/ui, TanStack Query. Final choices go through ADRs.
- Runs locally only: no hosting budget, no public attack surface.
- English for all code, docs and specs.

## Non-goals (v1)

- Multi-tenancy, accounts, billing.
- External auth providers, user accounts or SSO (API keys and an admin token only).
- Ordering guarantees.
- Kafka or any external broker.
- Payload filtering by field conditions or payload transformation (filters are event-type only).
- Public hosting, high availability, multi-region.
- Producer SDKs; receiver verification libraries (Standard Webhooks libraries can be used instead).
- Per-endpoint rate limiting (requests per second); v1 limits concurrency per endpoint, not rate.
- Global concurrency limits across several nodes (v1 runs one node).

## Risks

| Risk | Impact | Mitigation / next step |
|---|---|---|
| A slow or dead endpoint stalls other merchants' deliveries | Delays for healthy merchants | One Oban queue per endpoint with its own limit (ADR), strict timeouts, and a test plus load scenario with one slow endpoint. Owner: delivery spec. |
| Many endpoints mean many queue producers (one per endpoint) | Higher DB polling and memory at thousands of endpoints | Fine at demo scale; measure in the load test; fallback is an own dispatcher on the same tables (ADR). |
| SSRF rules block the local demo receiver, which runs on a private Docker network | Demo does not work | Host allowlist only in dev/demo config (FR-8). Owner: endpoint spec. |
| Elixir MCP libraries are young and change quickly | Rework of the MCP layer | Keep MCP a thin adapter over contexts; pin versions; ADR compares options. |
| Endpoint secrets must be readable to sign, so a DB dump leaks them | Forged webhooks | Encrypt secrets at rest (ADR). |
| Stored payloads may contain text that tries to steer an AI agent | Agent misuse of `resend_delivery` | Mark returned data as untrusted, keep mutation behind `write` scope, log every call. |
| Agent-built tasks drift from the spec | Hidden bugs | Each scenario → named ExUnit test; Smelt gate; human merge approval. |
| Similarity to the author's previous employer's system | Legal / reputation | Original design and code; public standards (Standard Webhooks); no private names or formats. |

## Open questions

| Question | Owner / next step |
|---|---|
| Exact N for `degraded` (FR-17) and default backoff numbers. | Settle in the delivery spec; adjust after the load test. |
| License for the public repo (proposal: MIT). | Author (ADR). |
