# Proposal

## Why

Events are accepted and fanned out to `pending` deliveries, but nothing sends them. This change delivers them: signed requests a receiver can verify with off-the-shelf libraries, retries that survive restarts and stop at the retry window, an append-only record of every attempt so support can answer "did the merchant get it, and when?", and one Oban queue per endpoint so a slow endpoint only uses its own share of concurrency (FR-11 to FR-16, FR-18 to FR-20, FR-35).

## What Changes

- **Signing**: Standard Webhooks headers (`webhook-id` = event id, `webhook-timestamp`, `webhook-signature` with one `v1,` signature per active secret, so two during a rotation's overlap) plus `courier-delivery-id`.
- **HTTP client**: Req with `retry: false`, no redirects, explicit connect and receive timeouts, and a connection pool per origin at least as large as the largest allowed `max_concurrency`. The URL policy runs again before every request.
- **Attempts**: a new `attempts` table, insert-only, protected by a database trigger that rejects `UPDATE` always and `DELETE` unless the transaction set `courier.retention = on` (used later by retention). Each row keeps the URL, redacted request headers, status, the first 4 KB of the response body, the duration and the error.
- **Worker**: one Oban job per pending delivery, in the queue of its endpoint. `2xx` → `succeeded`; network errors, timeouts, `408`, `429` and `5xx` → retry with capped exponential backoff and full jitter, honouring `Retry-After` on `429` and `503`; `3xx` and other `4xx` (unless the endpoint sets `retry_on_4xx`) → `failed`. Retries stop at the delivery's retry window, which becomes `failed` (dead letter). Delivery status only moves forward.
- **Queues**: `Courier.Delivery.QueueManager` starts one Oban queue per enabled endpoint (`endpoint:<id>`, limit `max_concurrency`) at boot, and starts, scales or stops it when an endpoint is created, updated, enabled or disabled.
- **Ingestion**: the jobs of an event's pending deliveries are inserted in the ingestion transaction. Two follow-ups from step 3: an event's deliveries are listed in one stable order (endpoint creation, then delivery id) everywhere, and a repeat for a merchant disabled after the original returns the original event (`200`) instead of `merchant_disabled`.
- **Read API**: `GET /api/v1/deliveries/:id` (scope `read`) returns a delivery with its attempts.
- Not in this change: the `degraded` flag and the slow-endpoint isolation test (FR-17, FR-36, next change `add-endpoint-health`), resend (step 5), telemetry and metrics beyond Oban's own (step 6).

## Capabilities

### New Capabilities
- `webhook-delivery`: signing, sending and retrying deliveries, recording attempts, per-endpoint queues, and reading a delivery's attempts.

### Modified Capabilities
- `event-ingestion`: deliveries get their jobs in the same transaction; a repeat for a merchant disabled after the original returns the original event; deliveries are listed in a stable order.

## Impact

- New modules under `lib/courier/delivery/` (signer, client, retry policy, worker, queue manager) and `lib/courier/audit/` (attempts); new `DeliveryController` and `DeliveryJSON`.
- New table `attempts` with a trigger; no change to existing tables.
- `Courier.Ingestion` and `Courier.Endpoints` call into the delivery context; `Courier.Application` starts a Finch pool and the queue manager after Oban.
- New dependency: `req` (named in `AGENTS.md` as the HTTP client, but not yet in `mix.exs`).
- Existing tests are not modified; the changed ingestion behaviour gets new tests in new files.
