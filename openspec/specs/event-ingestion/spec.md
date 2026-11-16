# event-ingestion Specification

## Purpose
Accepts events from the producer exactly once per idempotency key, validates them, and stores each event together with one delivery per interested endpoint, so that no accepted event is lost or delivered twice by mistake.

## Requirements

### Requirement: Accept events
The system SHALL accept `POST /api/v1/events` from a key with the `ingest` scope, with a JSON body holding `type`, `merchant_id`, `payload` and an optional `occurred_at` (ISO 8601; defaults to the time of receipt), and an `Idempotency-Key` header. It MUST answer `202` with the stored event and its deliveries.

#### Scenario: Event accepted
- **WHEN** the producer posts a `payment.succeeded` event for an enabled merchant with a new idempotency key
- **THEN** the response is `202` with the event's id, type, merchant id, payload, occurrence and receipt times, and its deliveries

#### Scenario: Occurrence time defaults to receipt
- **WHEN** the producer posts an event without `occurred_at`
- **THEN** the event's occurrence time equals its receipt time

#### Scenario: Wrong scope
- **WHEN** a key with only `read` and `write` posts an event
- **THEN** the response is `403` with code `forbidden` and nothing is stored

### Requirement: Idempotency key is required
The system SHALL require an `Idempotency-Key` header of 1 to 255 printable ASCII characters. A missing or malformed key MUST get `422` with code `invalid` and an error on `idempotency_key`, and nothing is stored.

#### Scenario: Missing key
- **WHEN** the producer posts an event without an `Idempotency-Key` header
- **THEN** the response is `422` with an error on `idempotency_key` and no event is stored

#### Scenario: Malformed key
- **WHEN** the producer posts an event with an empty key or one longer than 255 characters
- **THEN** the response is `422` with an error on `idempotency_key`

### Requirement: Repeats return the original event
The system SHALL treat a request whose idempotency key matches a stored event and whose `type`, `merchant_id`, `payload` and `occurred_at` are the same as a repeat: it MUST answer `200` with the original event and deliveries and store nothing new. Key order inside `payload` MUST NOT matter.

#### Scenario: Exact repeat
- **WHEN** the producer posts the same event twice with the same idempotency key
- **THEN** the second response is `200` with the same event id and deliveries, and only one event exists

#### Scenario: Same payload with keys in another order
- **WHEN** a repeat sends the same payload with its JSON object keys in a different order
- **THEN** it is treated as a repeat and answered `200` with the original event

### Requirement: Reused keys are rejected
The system SHALL reject a request whose idempotency key matches a stored event but whose `type`, `merchant_id`, `payload` or `occurred_at` differ, with `422` and code `idempotency_key_reused`, without changing anything.

#### Scenario: Key reused with a different body
- **WHEN** the producer posts a different payload with an idempotency key already used
- **THEN** the response is `422` with code `idempotency_key_reused` and the stored event is unchanged

### Requirement: Concurrent duplicates store one event
The system SHALL store exactly one event when several requests with the same key and body arrive at the same time; every request MUST receive that event.

#### Scenario: Simultaneous repeats
- **WHEN** five identical requests with the same key are processed concurrently
- **THEN** exactly one event and one set of deliveries exist, and every response carries that event's id

### Requirement: Validate events
The system SHALL reject, with `422` and nothing stored: an unknown merchant (error on `merchant_id`), a type that is not dot-separated lowercase segments of letters, digits and `_` (error on `type`), a `payload` that is not a JSON object (error on `payload`), and an `occurred_at` that is not ISO 8601 (error on `occurred_at`).

#### Scenario: Event for unknown merchant
- **WHEN** the producer posts an event for a merchant id that does not exist
- **THEN** the response is `422` with an error on `merchant_id` and no event is stored

#### Scenario: Invalid type or payload
- **WHEN** the producer posts an event with type `Payment Succeeded` or with a payload that is a list or a string
- **THEN** the response is `422` with an error on that field

### Requirement: Disabled merchants are rejected
The system SHALL reject events for a disabled merchant with `422` and code `merchant_disabled`, storing nothing. A request whose idempotency key matches an event stored before the merchant was disabled MUST be answered as for an enabled merchant: a repeat returns `200` with the original event, and a different body gets `422` with code `idempotency_key_reused`.

#### Scenario: Merchant disabled
- **WHEN** the producer posts an event for a merchant whose `enabled` is false
- **THEN** the response is `422` with code `merchant_disabled` and no event is stored

#### Scenario: Repeat after the merchant was disabled
- **WHEN** the producer repeats an accepted event with the same idempotency key and body after its merchant was disabled
- **THEN** the response is `200` with the original event and nothing new is stored

### Requirement: Payload size limit
The system SHALL reject an event whose payload, encoded as JSON, is larger than 256 KB with `413` and code `payload_too_large`, storing nothing.

#### Scenario: Payload too large
- **WHEN** the producer posts an event with a payload of 300 KB
- **THEN** the response is `413` with code `payload_too_large` and no event is stored

### Requirement: One delivery per interested endpoint
The system SHALL create, with the event, one delivery for each enabled endpoint of the merchant: `pending` when the endpoint's event-type filters match the event type, `skipped` otherwise. Disabled endpoints get no delivery. Each pending delivery MUST record the end of its retry window (receipt time plus the endpoint's retry window).

#### Scenario: Matching and filtered endpoints
- **WHEN** a merchant has an endpoint for `payment.*`, an endpoint for `refund.*` and a disabled endpoint, and a `payment.succeeded` event arrives
- **THEN** the first endpoint gets a `pending` delivery, the second a `skipped` one, and the disabled endpoint none

#### Scenario: Retry window recorded
- **WHEN** an event arrives for an endpoint with a retry window of 3600 seconds
- **THEN** its pending delivery's window ends 3600 seconds after the event's receipt time

#### Scenario: Merchant without endpoints
- **WHEN** an event arrives for an enabled merchant that has no enabled endpoints
- **THEN** the event is accepted with `202` and has no deliveries

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
