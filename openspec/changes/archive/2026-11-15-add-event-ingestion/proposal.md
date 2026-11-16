# Proposal

## Why

courier exists to deliver a producer's events to its merchants. With API keys, merchants and endpoints in place, the next step is accepting events safely: a payments producer retries on timeouts, so ingestion must be idempotent, and an accepted event must never be lost or half-stored (FR-1 to FR-5, FR-10).

## What Changes

- **Ingestion API**: `POST /api/v1/events` (scope `ingest`) accepts `type`, `merchant_id`, `payload` (a JSON object) and an optional `occurred_at`, with a required `Idempotency-Key` header. It answers `202` with the event and its deliveries.
- **Idempotency**: a repeat with the same key and the same body returns `200` with the original event and creates nothing; the same key with a different body returns `422` (`idempotency_key_reused`). Concurrent duplicates resolve to one event.
- **Validation**: unknown merchant, disabled merchant (`merchant_disabled`), invalid type, non-object payload, payload over 256 KB (`413`), and a missing or malformed key are rejected without storing anything.
- **Fan-out**: the event and one delivery per enabled endpoint of the merchant are stored in one transaction. A delivery is `pending` when the endpoint's filters match the type and `skipped` otherwise; disabled endpoints get none. Each delivery records when its retry window ends.
- **Read API** (scope `read`): `GET /api/v1/events` (paginated, filters by merchant and type) and `GET /api/v1/events/:id` with its deliveries.
- **Test support**: a shared helper to capture debug logs, and a working test for the `api-access` scenario "Rejected token not echoed" (the existing one cannot capture debug logs).
- Not in this change: sending deliveries and their Oban jobs (step 4 adds the jobs to the same transaction), resend (step 5), retention (step 13).

## Capabilities

### New Capabilities
- `event-ingestion`: accepting events idempotently, validating them, storing each event with its deliveries atomically, and reading events back.

### Modified Capabilities
None. (The `api-access` scenario "Rejected token not echoed" gets an extra test, but its requirement does not change.)

## Impact

- New contexts `Courier.Ingestion` (events) and `Courier.Delivery` (deliveries, only creation and reads for now); tables `events` and `deliveries`.
- New controller, JSON views and routes under `/api/v1`; a request-size bound in `Plug.Parsers`.
- New shared test helper in `test/support/`.
- No new dependencies.
