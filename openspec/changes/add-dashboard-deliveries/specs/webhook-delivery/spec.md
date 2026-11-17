## MODIFIED Requirements

### Requirement: Read a delivery with its attempts
The system SHALL let a key with the `read` scope get `GET /api/v1/deliveries/:id` with the delivery's status, creation time (`inserted_at`), event type, merchant id, attempt count, next attempt time, window end, completion time, `resend_of_id`, `triggered_by`, its direct resends (id, status, actor, creation time, oldest first) and its attempts in order, without request headers. An unknown or malformed id MUST get `404`.

#### Scenario: Delivery with attempts
- **WHEN** an operator requests a delivery that failed once and then succeeded
- **THEN** the response is `200` with status `succeeded` and two attempts numbered 1 and 2

#### Scenario: Unknown delivery
- **WHEN** an operator requests a delivery id that does not exist or is malformed
- **THEN** the response is `404` with code `not_found`

#### Scenario: Resend links
- **WHEN** an operator requests a delivery that was resent once, and then the resend
- **THEN** the first response lists the resend under `resends` with `triggered_by` `api_key:<name>`, and the second has `resend_of_id` equal to the first delivery

#### Scenario: Delivery shows its event and creation time
- **WHEN** an operator requests a delivery of a `payment.succeeded` event of merchant M
- **THEN** the response has `event_type` `payment.succeeded`, `merchant_id` M and the delivery's `inserted_at`

## ADDED Requirements

### Requirement: List deliveries
The system SHALL let a key with the `read` scope list deliveries with `GET /api/v1/deliveries`, newest first (by creation time, then id), with `limit` (1 to 100, default 50) and an opaque `cursor`, without attempts. Each item MUST carry its id, event id, event type, merchant id, endpoint id, status, attempt count, next attempt time, completion time, `resend_of_id`, `triggered_by` and creation time.

#### Scenario: Newest deliveries first
- **WHEN** an operator lists deliveries without filters
- **THEN** the response is `200` with the deliveries newest first, each with its event type and merchant id, and `next_cursor` set when more remain

#### Scenario: Pages follow the cursor
- **WHEN** there are three deliveries and an operator lists them with `limit=2`, then with the returned `next_cursor`
- **THEN** the first page has the two newest, the second the oldest and `next_cursor` null, with no delivery repeated

#### Scenario: Listing needs the read scope
- **WHEN** a key with only the `ingest` scope lists deliveries
- **THEN** the response is `403` with code `forbidden`

### Requirement: Filter deliveries
The delivery list SHALL accept these optional filters, combined with AND: `status` (`pending`, `succeeded`, `failed` or `skipped`), `merchant_id` (the event's merchant), `endpoint_id`, `event_id`, `event_type` (exact) and a time range on the creation time (`since` inclusive, `until` exclusive, ISO 8601 with a time zone). An unknown `status`, an invalid time or an invalid `limit` or `cursor` MUST get `422` with code `invalid`; a malformed id filter MUST match nothing.

#### Scenario: Filters combined
- **WHEN** an operator lists deliveries with `status=failed`, `merchant_id` M and `event_type=payment.succeeded`
- **THEN** only failed deliveries of M's `payment.succeeded` events are returned

#### Scenario: Filter by endpoint and event
- **WHEN** an operator lists deliveries with `endpoint_id` E, and then with `event_id` V
- **THEN** the first list has only E's deliveries and the second only V's

#### Scenario: Deliveries in a time range
- **WHEN** deliveries were created at 10:00, 11:00 and 12:00 and an operator lists them with `since` 10:30 and `until` 12:00
- **THEN** only the delivery created at 11:00 is returned

#### Scenario: Invalid filter rejected
- **WHEN** an operator lists deliveries with `status=lost`, or with `until=tomorrow`
- **THEN** the response is `422` with code `invalid`

#### Scenario: Malformed id matches nothing
- **WHEN** an operator lists deliveries with `endpoint_id=not-a-uuid`
- **THEN** the response is `200` with an empty list
