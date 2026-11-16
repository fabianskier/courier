# Spec Delta

## ADDED Requirements

### Requirement: Expired pending deliveries are swept
The system SHALL, at least every 5 minutes, mark `failed` without a new attempt every `pending` delivery whose retry window has ended, and cancel its delivery job, including deliveries of disabled endpoints whose queues are stopped.

#### Scenario: Delivery of a disabled endpoint expires
- **WHEN** an endpoint is disabled with a pending delivery and the delivery's window then ends
- **THEN** the next sweep marks the delivery `failed` with `completed_at` set, stores no attempt and cancels its job

#### Scenario: Pending delivery inside its window is kept
- **WHEN** the sweep runs and a pending delivery's window has not ended
- **THEN** the delivery stays `pending` and its job is untouched
