---
name: webhook-reliability
description: Domain rules for reliable webhook delivery: idempotency, retries with backoff, signatures, audit trail, manual resend and endpoint safety. Use when designing or implementing event ingestion and delivery to merchant endpoints.
---

# Reliable webhook delivery

The goal is **at-least-once delivery that is safe to repeat**. Receivers will see duplicates sometimes; design so that is harmless.

## Ingestion and idempotency

- The producer sends an idempotency key with each event. Store it with a **unique constraint**; a repeat returns the original event, it does not create a new one.
- Give each delivery a stable `delivery_id` and send it to the receiver in a header so they can de-duplicate on their side.
- Accept the event first, deliver later: persist, then enqueue. If enqueueing fails, the event must not be lost.

## Delivery and retries

- Use explicit connect and receive timeouts on every request.
- **One layer owns retries.** The job queue schedules retries with the backoff policy below, so the HTTP client must not retry on its own; otherwise attempts multiply and the audit trail stops matching reality.
- Classify results:
  - `2xx`: success.
  - Network error, timeout, `408`, `429`, `5xx`: retry.
  - Other `4xx`: do not retry by default (a configurable policy per endpoint).
- Respect `Retry-After` on `429` and `503` when present.
- Backoff is exponential, with **jitter**, capped, inside a configurable retry window (for example up to 24 hours). When the window ends, mark the delivery `failed` (dead-letter state), never drop it silently.
- Ordering is **not** guaranteed. Say so in the docs; receivers use event timestamps or versions.

## Signatures

- Sign `"<timestamp>.<raw_body>"` with HMAC-SHA256 using a per-endpoint secret; send the timestamp and the signature in headers.
- Receivers must compare in constant time (`Plug.Crypto.secure_compare/2`) and reject old timestamps to stop replays.
- Support secret rotation: accept the old and the new secret for a limited overlap.
- Never log secrets or full signatures.

## Audit trail

- Every attempt is an **append-only** row: delivery id, attempt number, start time, duration, request summary, response status, a truncated response body, and the error if any.
- Support must be able to answer "did the merchant get this event, and when?" from this table alone.
- Truncate stored bodies and redact sensitive headers.

## Manual resend

- A resend creates a **new delivery linked to the original**. It never rewrites history.
- It reuses the same event and the same idempotency semantics, and records who triggered it.

## Per-merchant rules

- Filters decide which events or payload types an endpoint receives. A filtered-out event is recorded as skipped, not as missing.

## Endpoint safety

- Validate endpoint URLs: require `https` outside development and block private, loopback and link-local addresses to avoid SSRF. Re-check after DNS resolution.
- Limit payload size and the number of redirects (prefer none).
- After N consecutive failures, mark the endpoint as degraded and alert; do not hammer a dead endpoint forever.

## Observability

- Emit telemetry for attempts, successes, failures, retry counts and queue lag, and expose them on a dashboard.
