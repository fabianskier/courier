# Proposal

## Why

Events are delivered to merchants' HTTPS endpoints, so courier must know the merchants, where to send their webhooks, which event types each endpoint wants and the secret that signs each request (FR-6 to FR-9). Ingestion (step 3) and delivery (step 4) both depend on this, and the endpoint URL is the main attack surface of a webhook sender (SSRF), so it must be validated from the start.

## What Changes

- **Merchants**: create, list, show, rename and enable or disable a merchant.
- **Endpoints** belong to a merchant and have a URL, a description, event-type patterns, an enabled flag and delivery settings used by later changes (retry window up to 24 h, retry on `4xx`, maximum concurrency).
- **Signing secrets**: each endpoint gets a secret in the Standard Webhooks format (`whsec_…`), returned only when the endpoint is created or its secret is rotated, and stored encrypted at rest. Rotating keeps the previous secret valid for an overlap window (24 h) so receivers can switch without losing webhooks.
- **URL safety**: endpoint URLs must use `https` (plain `http` only where configured, as in development), may not carry credentials, and must not point to private, loopback, link-local or other non-public addresses, checked after DNS resolution; an explicit host allowlist covers the local demo receiver.
- **Event-type filters**: a list of exact types (`payment.succeeded`) or prefix wildcards (`payment.*`); an empty list matches every type. Invalid patterns are rejected.
- **REST API** under `/api/v1`: `read` scope to list and show merchants and endpoints, `write` scope to create, update and rotate secrets. Lists are paginated with a limit and an opaque cursor.
- Quieter Mix tasks: `mix courier.keys.*` no longer print Ecto's SQL debug lines in development.
- New dependency: `cloak_ecto` (application-level encryption, as decided in the ADR "Encrypt endpoint secrets at rest").

## Capabilities

### New Capabilities
- `merchants`: the merchants that own endpoints, their lifecycle and their API.
- `webhook-endpoints`: merchant endpoints with URL safety rules, event-type filters, delivery settings, signing secrets with rotation, and their API.

### Modified Capabilities
None.

## Impact

- New contexts `Courier.Merchants` and `Courier.Endpoints`, tables `merchants` and `endpoints`, `Courier.Vault` (Cloak) and an encrypted binary Ecto type.
- New configuration: `COURIER_ENCRYPTION_KEY` (required in production), URL policy (`require_https`, `allowed_hosts`) per environment.
- New controllers, JSON views and routes under `/api/v1`; a shared cursor pagination helper reused by later list endpoints.
- New dependencies: `cloak_ecto` (and `cloak`), MIT licensed.
- Not in this change: per-endpoint Oban queues and the degraded flag (delivery change), re-checking the URL before each request (delivery change), the dashboard screens (step 11).
