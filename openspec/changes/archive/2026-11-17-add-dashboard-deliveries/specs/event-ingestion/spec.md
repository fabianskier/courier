## MODIFIED Requirements

### Requirement: Read events
The system SHALL let a key with the `read` scope list events newest first with pagination, optionally filtered by `merchant_id`, exact `type` and a time range on the received time (`since` inclusive, `until` exclusive, both ISO 8601 with a time zone), and show one event with its deliveries. A `since` or `until` that is not a valid ISO 8601 timestamp MUST get `422` with code `invalid`. An unknown or malformed id MUST get `404`. An event's deliveries MUST be listed in the same order in every response (the ingestion response, a repeat and a read): by endpoint creation, then by delivery creation.

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

#### Scenario: Events in a time range
- **WHEN** events were received at 10:00, 11:00 and 12:00 and an operator lists events with `since` 10:30 and `until` 12:00
- **THEN** only the event received at 11:00 is returned

#### Scenario: Invalid time range rejected
- **WHEN** an operator lists events with `since=yesterday`
- **THEN** the response is `422` with code `invalid`
