# Spec Delta

## MODIFIED Requirements

### Requirement: Read a delivery with its attempts
The system SHALL let a key with the `read` scope get `GET /api/v1/deliveries/:id` with the delivery's status, attempt count, next attempt time, window end, completion time, `resend_of_id`, `triggered_by`, its direct resends (id, status, actor, creation time, oldest first) and its attempts in order, without request headers. An unknown or malformed id MUST get `404`.

#### Scenario: Delivery with attempts
- **WHEN** an operator requests a delivery that failed once and then succeeded
- **THEN** the response is `200` with status `succeeded` and two attempts numbered 1 and 2

#### Scenario: Unknown delivery
- **WHEN** an operator requests a delivery id that does not exist or is malformed
- **THEN** the response is `404` with code `not_found`

#### Scenario: Resend links
- **WHEN** an operator requests a delivery that was resent once, and then the resend
- **THEN** the first response lists the resend under `resends` with `triggered_by` `api_key:<name>`, and the second has `resend_of_id` equal to the first delivery
