# endpoint-health Specification

## Purpose
Tracks each endpoint's consecutive failed attempts, marks endpoints degraded when failures reach a threshold and clears the mark on the next success, emits telemetry for both transitions, and keeps endpoints isolated so a slow one never delays deliveries to the others.

## Requirements

### Requirement: Consecutive failures are counted
The system SHALL count, per endpoint, the attempts that did not get a `2xx` since its last success, updating the count in the same transaction that stores the attempt. A `2xx` attempt MUST reset the count to zero.

#### Scenario: Failures counted and reset
- **WHEN** an endpoint gets three failed attempts (a `500`, a timeout and a `400`) and then a `200`
- **THEN** its consecutive failures are 1, 2 and 3 after each failure and 0 after the success

#### Scenario: No attempt, no count
- **WHEN** a pending delivery is failed because its window ended, without an attempt
- **THEN** its endpoint's consecutive failures do not change

### Requirement: Degraded endpoints
The system SHALL mark an endpoint degraded, with the time, when its consecutive failures reach the threshold (default 20, configurable), and emit the telemetry event `[:courier, :endpoint, :degraded]` once. The next successful attempt MUST clear the mark and emit `[:courier, :endpoint, :recovered]`. A degraded endpoint MUST keep receiving attempts.

#### Scenario: Endpoint becomes degraded
- **WHEN** an endpoint with threshold 3 gets its third consecutive failed attempt
- **THEN** `degraded_at` is set and one `[:courier, :endpoint, :degraded]` event is emitted with the endpoint id and the count

#### Scenario: Further failures emit no new event
- **WHEN** a degraded endpoint gets another failed attempt
- **THEN** `degraded_at` keeps its value and no new degraded event is emitted

#### Scenario: Endpoint recovers
- **WHEN** a degraded endpoint gets a `2xx` attempt
- **THEN** `degraded_at` is cleared, the count is 0 and one `[:courier, :endpoint, :recovered]` event is emitted

#### Scenario: Degraded endpoint still retried
- **WHEN** a delivery to a degraded endpoint fails with `503` inside its window
- **THEN** the delivery stays `pending` with a next attempt scheduled

### Requirement: Endpoints are isolated from each other
The system SHALL run each endpoint's deliveries so that an endpoint that is slow on every request does not delay the first attempt of another endpoint's delivery.

#### Scenario: Slow endpoint does not delay another
- **WHEN** one endpoint takes 3 seconds to answer and has more jobs than its concurrency limit, and a delivery for another endpoint is then created
- **THEN** the other endpoint's delivery succeeds within 2 seconds of its creation while the slow endpoint still has jobs running
