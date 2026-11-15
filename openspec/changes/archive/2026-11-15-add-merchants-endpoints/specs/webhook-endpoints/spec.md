# Spec Delta

## Purpose

Keeps the HTTPS endpoints that receive a merchant's webhooks: where they are, which events they want, how deliveries to them behave and the secrets that sign them, with rules that stop endpoints from targeting internal networks.

## ADDED Requirements

### Requirement: Create endpoints
The system SHALL create an endpoint for an existing merchant from a URL, an optional description, event-type patterns and optional delivery settings. A new endpoint MUST be enabled. The response MUST include the endpoint's signing secret; no later read returns it.

#### Scenario: Endpoint created
- **WHEN** an operator with `write` scope sends `POST /api/v1/endpoints` with a merchant id, url `https://hooks.example.com/courier` and event types `["payment.*"]`
- **THEN** the response is `201` with the endpoint, `enabled: true`, the default delivery settings and a `secret` starting with `whsec_`

#### Scenario: Endpoint for unknown merchant
- **WHEN** an operator creates an endpoint with a merchant id that does not exist
- **THEN** the response is `422` with code `invalid` and an error on `merchant_id`

### Requirement: Delivery settings
The system SHALL store per-endpoint delivery settings with defaults: retry window in seconds (default and maximum 86400, minimum 60), whether to retry `4xx` responses (default false), and maximum concurrency (default 10, between 1 and 50). Values outside these ranges MUST be rejected.

#### Scenario: Defaults applied
- **WHEN** an endpoint is created without delivery settings
- **THEN** it has a retry window of 86400 seconds, does not retry `4xx`, and has a maximum concurrency of 10

#### Scenario: Setting out of range
- **WHEN** an operator creates or updates an endpoint with a retry window of 90000 seconds or a maximum concurrency of 0
- **THEN** the response is `422` with code `invalid` and an error on that field

### Requirement: Endpoint URLs are safe
The system SHALL accept only absolute URLs with scheme `https` (or `http` where the environment allows it), a host, and no user info. The host MUST resolve only to public addresses: loopback, private, link-local, unspecified, multicast, carrier-grade NAT and their IPv6 equivalents are rejected, unless the host is on the configured allowlist. A host that does not resolve MUST be rejected.

#### Scenario: Plain http rejected
- **WHEN** an operator creates an endpoint with url `http://hooks.example.com/courier` in an environment that requires https
- **THEN** the response is `422` with code `invalid` and an error on `url`

#### Scenario: Private address rejected
- **WHEN** an operator creates an endpoint whose host is `127.0.0.1`, `10.0.0.5`, `169.254.169.254`, `[::1]`, or a name that resolves to one of them
- **THEN** the response is `422` with code `invalid` and an error on `url`

#### Scenario: Credentials in URL rejected
- **WHEN** an operator creates an endpoint with url `https://user:pass@hooks.example.com/`
- **THEN** the response is `422` with code `invalid` and an error on `url`

#### Scenario: Unresolvable host rejected
- **WHEN** an operator creates an endpoint whose host does not resolve
- **THEN** the response is `422` with code `invalid` and an error on `url`

#### Scenario: Allowlisted host accepted
- **WHEN** the allowlist contains `demo-receiver` and an operator creates an endpoint with url `http://demo-receiver:4001/hooks` in an environment that allows http
- **THEN** the endpoint is created even though the host resolves to a private address

### Requirement: Event-type filters
The system SHALL store a list of event-type patterns per endpoint. Each pattern MUST be an exact type of dot-separated lowercase segments (letters, digits, `_`) or such a prefix followed by `.*`. An empty list matches every type; otherwise an event type matches when it equals an exact pattern or starts with a wildcard's prefix followed by a dot.

#### Scenario: Exact and wildcard matching
- **WHEN** an endpoint has patterns `["payment.*", "refund.failed"]`
- **THEN** `payment.succeeded` and `payment.card.declined` match, `refund.failed` matches, and `refund.succeeded` and `payments.created` do not

#### Scenario: Empty list matches everything
- **WHEN** an endpoint has no patterns
- **THEN** every event type matches

#### Scenario: Invalid pattern rejected
- **WHEN** an operator sets patterns such as `"*"`, `"Payment.Succeeded"`, `"payment.*.failed"` or `""`
- **THEN** the response is `422` with code `invalid` and an error on `event_types`

### Requirement: Show, list, update and disable endpoints
The system SHALL show an endpoint by id, list endpoints oldest first with pagination (optionally for one merchant), and update its URL, description, patterns, enabled flag and delivery settings with the same validation as creation. Endpoints are never deleted, and no response other than create and rotate MUST contain a secret.

#### Scenario: List a merchant's endpoints
- **WHEN** an operator with `read` scope sends `GET /api/v1/endpoints?merchant_id=<id>`
- **THEN** the response lists only that merchant's endpoints, without secrets

#### Scenario: Show without secret
- **WHEN** an operator sends `GET /api/v1/endpoints/:id`
- **THEN** the response is `200` with the endpoint and no `secret` field

#### Scenario: Disable an endpoint
- **WHEN** an operator with `write` scope sends `PATCH /api/v1/endpoints/:id` with `enabled: false`
- **THEN** the endpoint is disabled and still listed

#### Scenario: Unsafe URL on update
- **WHEN** an operator updates an endpoint's url to `https://10.0.0.5/`
- **THEN** the response is `422` with code `invalid` and the endpoint keeps its previous url

### Requirement: Signing secrets
The system SHALL generate each secret as `whsec_` followed by the base64 encoding of 32 cryptographically secure random bytes, and store it encrypted at rest. The stored value MUST NOT contain the secret in plaintext.

#### Scenario: Secret format
- **WHEN** an endpoint is created
- **THEN** its secret starts with `whsec_` and the rest decodes from base64 to 32 bytes

#### Scenario: Secret encrypted at rest
- **WHEN** an endpoint is created
- **THEN** the endpoint's row in the database does not contain the secret or its base64 part in plaintext

### Requirement: Rotate signing secrets
The system SHALL rotate an endpoint's secret on request: it returns a new secret once, keeps the previous one valid for an overlap of 24 hours, and reports which secrets currently sign. After the overlap only the new secret signs. Rotating again during an overlap replaces the previous secret with the current one.

#### Scenario: Rotation with overlap
- **WHEN** an operator with `write` scope sends `POST /api/v1/endpoints/:id/rotate_secret`
- **THEN** the response is `200` with a new secret, and the endpoint's signing secrets are the new one and the old one

#### Scenario: Overlap ends
- **WHEN** more than 24 hours have passed since a rotation
- **THEN** the endpoint's signing secrets are only the new one

### Requirement: Endpoint API scopes
The system SHALL require the `read` scope to list and show endpoints and the `write` scope to create, update and rotate them.

#### Scenario: Read-only key cannot rotate
- **WHEN** a key with only `read` sends `POST /api/v1/endpoints/:id/rotate_secret`
- **THEN** the response is `403` with code `forbidden` and the secret is unchanged
