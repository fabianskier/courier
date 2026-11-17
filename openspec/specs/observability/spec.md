# observability Specification

## Purpose
Lets operators see what courier is doing without reading the database: telemetry events for ingestion, attempts, delivery outcomes and queue lag, emitted once per committed change and without payloads or secrets, metrics for each of them, and a LiveDashboard that only an admin can open.

## Requirements

### Requirement: Ingestion telemetry
The system SHALL emit `[:courier, :event, :ingested]` once for each new event, after it is stored, with the number of deliveries and of pending deliveries as measurements and the merchant id and type as metadata. A repeat MUST NOT emit it.

#### Scenario: New event emits ingested
- **WHEN** an event with one pending and one skipped delivery is ingested
- **THEN** one `[:courier, :event, :ingested]` event is emitted with `deliveries` 2 and `pending` 1

#### Scenario: Repeat emits nothing
- **WHEN** the same event is posted again with the same idempotency key
- **THEN** no `[:courier, :event, :ingested]` event is emitted for the repeat

### Requirement: Attempt telemetry
The system SHALL emit `[:courier, :attempt, :start]` before each request and `[:courier, :attempt, :stop]` after it, with the duration, the time since the delivery was created, and the attempt number, outcome, status and status class as metadata. Metadata MUST NOT include payloads, response bodies, headers or secrets.

#### Scenario: Attempt start and stop
- **WHEN** a delivery's first attempt gets `503`
- **THEN** a start event and a stop event are emitted for attempt 1, the stop with outcome `retry`, status 503, status class `5xx`, a duration and `since_created_ms`

#### Scenario: Network error
- **WHEN** an attempt times out
- **THEN** the stop event has outcome `retry`, status `nil` and status class `error`

### Requirement: Delivery outcome telemetry
The system SHALL emit, after commit, `[:courier, :delivery, :succeeded]` when a delivery succeeds, `[:courier, :delivery, :failed]` with reason `non_retryable` or `window_ended` when it fails, and `[:courier, :delivery, :retry_scheduled]` with the delay when a retry is scheduled, each once per change.

#### Scenario: Succeeded
- **WHEN** a delivery succeeds on its second attempt
- **THEN** one succeeded event is emitted with `attempts` 2 and `total_ms`

#### Scenario: Failed for good
- **WHEN** a delivery gets `400`
- **THEN** one failed event is emitted with reason `non_retryable`

#### Scenario: Window ended
- **WHEN** a pending delivery is failed because its window ended
- **THEN** one failed event is emitted with reason `window_ended`

#### Scenario: Retry scheduled
- **WHEN** an attempt fails with `500` inside the window
- **THEN** one retry_scheduled event is emitted with the delay in seconds

### Requirement: Queue lag telemetry
The system SHALL measure every 10 seconds, for each endpoint queue with available jobs, how long its oldest available job has been waiting and how many are available, and emit `[:courier, :queue, :lag]` with the queue name as metadata.

#### Scenario: Waiting jobs measured
- **WHEN** an endpoint queue has two available jobs, the oldest runnable for 30 seconds
- **THEN** the measurement emits one lag event for that queue with `seconds` of at least 30 and `available` 2

#### Scenario: Empty queues are silent
- **WHEN** no endpoint queue has available jobs
- **THEN** the measurement emits no lag event

### Requirement: Metrics for every event
The system SHALL define at least one LiveDashboard metric for each courier telemetry event, including the time from a delivery's creation to its first attempt.

#### Scenario: Metrics defined
- **WHEN** the metrics list is read
- **THEN** it has a metric for each of the ingested, attempt stop, attempt exception, delivery succeeded, failed and retry scheduled, endpoint degraded and recovered, and queue lag events

### Requirement: Admin-only dashboard
The system SHALL serve LiveDashboard at `/admin/dashboard` only to requests with HTTP Basic credentials whose password equals the configured admin token, compared in constant time. Without credentials or with a wrong password it MUST answer `401` with a `www-authenticate` header; when no admin token is configured it MUST answer `404`. The token MUST NOT be logged.

#### Scenario: Correct token
- **WHEN** a request to `/admin/dashboard` sends Basic credentials with the admin token as password
- **THEN** the dashboard is served

#### Scenario: Missing or wrong token
- **WHEN** a request sends no credentials, or a wrong password
- **THEN** the response is `401` with a `www-authenticate` header

#### Scenario: Dashboard disabled
- **WHEN** no admin token is configured
- **THEN** `/admin/dashboard` answers `404`

### Requirement: Queue lag measured with the database up
The system SHALL start the periodic measurements, including the queue lag, after the database repository, and SHALL stop them before it, so no measurement runs while the repository is unavailable.

#### Scenario: Telemetry starts after the repo
- **WHEN** the application has started
- **THEN** `Courier.Repo` was started before `CourierWeb.Telemetry`
