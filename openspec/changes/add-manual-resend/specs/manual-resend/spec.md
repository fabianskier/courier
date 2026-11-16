# Spec Delta

## ADDED Requirements

### Requirement: Resend a terminal delivery
The system SHALL let a key with the `write` scope resend a delivery that is `succeeded`, `failed` or `skipped` with `POST /api/v1/deliveries/:id/resend`. It MUST create a new `pending` delivery for the same event and endpoint with `resend_of_id` set to the resent delivery, `triggered_by` set to `api_key:<key name>`, a retry window starting now, and its delivery job, all in one transaction, and answer `202` with the new delivery. The resent delivery and its attempts MUST NOT change.

#### Scenario: Resend a failed delivery
- **WHEN** an operator resends a `failed` delivery with a `write` key named `ops`
- **THEN** the response is `202` with a new `pending` delivery whose `resend_of_id` is the failed delivery and `triggered_by` is `api_key:ops`, and a delivery job exists for it in the endpoint's queue

#### Scenario: Original unchanged
- **WHEN** a delivery with two attempts is resent
- **THEN** its status, `completed_at`, attempt count and attempts are the same as before

#### Scenario: Resend a skipped delivery
- **WHEN** an operator resends a `skipped` delivery
- **THEN** a new `pending` delivery is created for the same endpoint

#### Scenario: Resend a resend
- **WHEN** an operator resends a delivery that is itself a succeeded resend
- **THEN** the new delivery's `resend_of_id` is that resend

#### Scenario: Wrong scope
- **WHEN** a key with only `read` resends a delivery
- **THEN** the response is `403` with code `forbidden` and nothing is created

### Requirement: Deliveries in progress are not resent
The system SHALL answer `409` with code `delivery_in_progress` when the delivery is `pending`, and `409` with code `resend_in_progress` when the delivery already has a `pending` resend, creating nothing. Concurrent resends of one delivery MUST create at most one new delivery.

#### Scenario: Pending delivery
- **WHEN** an operator resends a `pending` delivery
- **THEN** the response is `409` with code `delivery_in_progress` and no delivery is created

#### Scenario: Double resend
- **WHEN** an operator resends a `failed` delivery twice in a row while the first resend is still `pending`
- **THEN** the second response is `409` with code `resend_in_progress` and only one resend exists

#### Scenario: Simultaneous resends
- **WHEN** two resends of the same `failed` delivery run at the same time
- **THEN** exactly one new delivery is created

### Requirement: Resends need an enabled endpoint
The system SHALL answer `422` with code `endpoint_disabled` when the delivery's endpoint is disabled, creating nothing, and `404` with code `not_found` for an unknown or malformed delivery id.

#### Scenario: Endpoint disabled
- **WHEN** an operator resends a delivery whose endpoint is disabled
- **THEN** the response is `422` with code `endpoint_disabled` and no delivery is created

#### Scenario: Unknown delivery
- **WHEN** an operator resends a delivery id that does not exist or is malformed
- **THEN** the response is `404` with code `not_found`

### Requirement: Resends keep the webhook id
The system SHALL send a resend with `webhook-id` equal to the event id, as for the original delivery, and `courier-delivery-id` equal to the new delivery's id.

#### Scenario: Same webhook id
- **WHEN** a resend's job runs
- **THEN** the request's `webhook-id` is the event id and its `courier-delivery-id` is the resend's id
