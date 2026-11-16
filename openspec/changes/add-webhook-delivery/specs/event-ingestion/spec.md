# Spec Delta

## MODIFIED Requirements

### Requirement: Disabled merchants are rejected
The system SHALL reject events for a disabled merchant with `422` and code `merchant_disabled`, storing nothing. A request whose idempotency key matches an event stored before the merchant was disabled MUST be answered as for an enabled merchant: a repeat returns `200` with the original event, and a different body gets `422` with code `idempotency_key_reused`.

#### Scenario: Merchant disabled
- **WHEN** the producer posts an event for a merchant whose `enabled` is false
- **THEN** the response is `422` with code `merchant_disabled` and no event is stored

#### Scenario: Repeat after the merchant was disabled
- **WHEN** the producer repeats an accepted event with the same idempotency key and body after its merchant was disabled
- **THEN** the response is `200` with the original event and nothing new is stored

### Requirement: Events are stored atomically
The system SHALL store an event, all its deliveries and one delivery job per pending delivery in one transaction: either all of them exist or none does.

#### Scenario: Failure while storing deliveries
- **WHEN** storing one of an event's deliveries fails
- **THEN** neither the event nor any of its deliveries is stored

#### Scenario: Jobs stored with the event
- **WHEN** an event creates one pending and one skipped delivery
- **THEN** exactly one delivery job exists, for the pending delivery

#### Scenario: Failure while storing jobs
- **WHEN** storing an event's delivery jobs fails
- **THEN** neither the event, its deliveries nor any job is stored

### Requirement: Read events
The system SHALL let a key with the `read` scope list events newest first with pagination, optionally filtered by `merchant_id` and exact `type`, and show one event with its deliveries. An unknown or malformed id MUST get `404`. An event's deliveries MUST be listed in the same order in every response (the ingestion response, a repeat and a read): by endpoint creation, then by delivery creation.

#### Scenario: List and filter events
- **WHEN** an operator lists events with `merchant_id` and `type=payment.succeeded`
- **THEN** only that merchant's `payment.succeeded` events are returned, newest first

#### Scenario: Show an event with its deliveries
- **WHEN** an operator requests `GET /api/v1/events/:id`
- **THEN** the response is `200` with the event and each delivery's id, endpoint id and status

#### Scenario: Unknown event
- **WHEN** an operator requests an event id that does not exist or is malformed
- **THEN** the response is `404` with code `not_found`

#### Scenario: Stable delivery order
- **WHEN** an event fans out to three endpoints and is then read back
- **THEN** the ingestion response and the read list the deliveries in the endpoints' creation order
