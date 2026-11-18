# data-retention Specification

## Purpose
Keeps the database bounded: old events whose deliveries are all finished are deleted with their deliveries and attempts once a day, after a configurable period, without weakening the append-only rule for any other code.

## Requirements

### Requirement: Retention period
The system SHALL read the retention period in whole days from `COURIER_RETENTION_DAYS`, defaulting to 30 when it is not set. A value below 2 or that is not a whole number MUST stop the system at boot with a message naming the variable.

#### Scenario: Default period
- **WHEN** `COURIER_RETENTION_DAYS` is not set
- **THEN** the retention period is 30 days

#### Scenario: Configured period
- **WHEN** `COURIER_RETENTION_DAYS` is `7`
- **THEN** the retention period is 7 days

#### Scenario: Invalid period rejected
- **WHEN** `COURIER_RETENTION_DAYS` is `1` or `soon`
- **THEN** the system does not start, and the error names `COURIER_RETENTION_DAYS`

### Requirement: Old finished events are pruned
The pruning SHALL delete an event, its deliveries and their attempts when every delivery of the event is terminal (`succeeded`, `failed` or `skipped`) and the event's last activity, the later of its insertion and its latest delivery completion, is older than the retention period. An event with a `pending` delivery, or whose last activity is within the period, MUST be kept with all its rows.

#### Scenario: Old finished event pruned
- **WHEN** an event was received 40 days ago and its two deliveries completed 39 days ago, with a period of 30 days
- **THEN** the event, both deliveries and all their attempts are deleted

#### Scenario: Pending delivery keeps the event
- **WHEN** an event was received 40 days ago and one of its deliveries is still `pending`
- **THEN** the event and all its deliveries and attempts are kept

#### Scenario: Recent resend keeps an old event
- **WHEN** an event was received 40 days ago and a resend of one of its deliveries completed yesterday
- **THEN** the event and all its deliveries, including the resend, are kept

#### Scenario: Event with resends pruned together
- **WHEN** an old finished event has a delivery and a resend of it, both completed 35 days ago
- **THEN** the event, both deliveries and their attempts are deleted

### Requirement: Deletion respects append-only attempts
The pruning SHALL delete attempts only inside transactions that set `courier.retention` to `on` locally, in batches of at most 1,000 events per transaction. Any other deletion of an attempt MUST still be rejected by the database.

#### Scenario: Batched pruning
- **WHEN** 2,500 events are due for pruning
- **THEN** they are deleted in three transactions of at most 1,000 events each, and all of them are gone at the end

#### Scenario: Delete outside the job rejected
- **WHEN** code deletes an attempt in a transaction that did not set `courier.retention`
- **THEN** the database rejects the delete

### Requirement: Daily job and report
The system SHALL run the pruning once a day as a background job. Each run MUST report the number of events, deliveries and attempts deleted as a telemetry event and one `info` log line, also when nothing was deleted.

#### Scenario: Run reported
- **WHEN** a run deletes 3 events with 5 deliveries and 9 attempts
- **THEN** a telemetry event carries the counts 3, 5 and 9, and one `info` log line states them

#### Scenario: Scheduled daily
- **WHEN** the system's scheduled jobs are listed
- **THEN** the retention job is scheduled once a day in the `maintenance` queue

### Requirement: Idempotency keys after pruning
Once an event is pruned, its idempotency key SHALL be free: an ingestion with that key creates a new event.

#### Scenario: Key reused after pruning
- **WHEN** an event with key `order-42` was pruned and a producer sends a new event with key `order-42`
- **THEN** the response is `202` and a new event is created
