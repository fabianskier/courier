# webhook-delivery Specification

## Purpose
Sends each pending delivery to its endpoint as a signed Standard Webhooks request, retries retryable failures with capped backoff until the delivery's retry window ends, records every attempt in an append-only table, and runs each endpoint's deliveries in its own queue, so that support can always tell whether and when a merchant received an event.

## Requirements

### Requirement: Signed webhook requests
The system SHALL send each delivery as a `POST` of the event as JSON (`id`, `type`, `timestamp`, `merchant_id`, `data`) with the Standard Webhooks headers `webhook-id` (the event id), `webhook-timestamp` (Unix seconds) and `webhook-signature`, plus `courier-delivery-id`. The signature MUST be `v1,` followed by the base64 HMAC-SHA256 of `id.timestamp.body` with the endpoint's secret, and MUST hold one signature per secret that currently signs for the endpoint.

#### Scenario: Standard Webhooks test vector
- **WHEN** the signer signs id `msg_p5jXN8AQM9LWM0D4loKWxJek`, timestamp `1614265330` and body `{"test": 2432232314}` with secret `whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw`
- **THEN** the signature header is `v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=`

#### Scenario: Two signatures during rotation
- **WHEN** a delivery is sent to an endpoint whose secret was rotated less than 24 hours ago
- **THEN** `webhook-signature` holds two space-separated `v1,` signatures, one valid with the new secret and one with the previous secret

#### Scenario: Request headers and body
- **WHEN** a delivery is sent
- **THEN** the request is a `POST` to the endpoint URL whose body is the event JSON, with `webhook-id` equal to the event id and `courier-delivery-id` equal to the delivery id

### Requirement: Successful delivery
The system SHALL mark a delivery `succeeded`, with its completion time, when the endpoint answers `2xx`.

#### Scenario: Endpoint answers 200
- **WHEN** a pending delivery is sent and the endpoint answers `200`
- **THEN** the delivery is `succeeded` with `completed_at` set and one attempt is stored with status `200`

### Requirement: Retryable failures are retried
The system SHALL retry a delivery after a network error, a timeout, `408`, `429` or `5xx`, keeping it `pending` with the time of the next attempt. Another `4xx` MUST be retried only when the endpoint sets `retry_on_4xx`.

#### Scenario: Server error
- **WHEN** the endpoint answers `503` without `Retry-After`
- **THEN** an attempt is stored, the delivery stays `pending` with `next_attempt_at` set, and the job is snoozed until then

#### Scenario: Timeout
- **WHEN** the request times out
- **THEN** an attempt is stored with no response status and an error, and the delivery is retried

#### Scenario: 4xx retried when configured
- **WHEN** the endpoint has `retry_on_4xx` true and answers `404`
- **THEN** the delivery stays `pending` and is retried

### Requirement: Non-retryable failures end the delivery
The system SHALL mark a delivery `failed` after one attempt when the endpoint answers `3xx`, or a `4xx` other than `408` and `429` while `retry_on_4xx` is false. Redirects MUST NOT be followed.

#### Scenario: Client error
- **WHEN** the endpoint answers `400`
- **THEN** one attempt is stored and the delivery is `failed` with `completed_at` set

#### Scenario: Redirect not followed
- **WHEN** the endpoint answers `302` with a `location` header
- **THEN** no request is sent to the location, one attempt is stored with status `302`, and the delivery is `failed`

### Requirement: Backoff with jitter and Retry-After
The system SHALL wait before attempt `n + 1` a random time between 1 second and `1 + min(3600, 10 × 2^(n-1))` seconds. A `Retry-After` header (seconds or HTTP date) on `429` or `503` MUST be honoured when it asks for longer, capped at 3600 seconds.

#### Scenario: Delay grows and is capped
- **WHEN** the delay is computed for attempts 1, 2 and 20 with the largest random value
- **THEN** it is 11, 21 and 3601 seconds

#### Scenario: Retry-After honoured
- **WHEN** the endpoint answers `429` with `Retry-After: 120` after the first attempt
- **THEN** the next attempt is scheduled at least 120 seconds later

#### Scenario: Retry-After capped
- **WHEN** the endpoint answers `503` with `Retry-After: 86400` after the first attempt
- **THEN** the next attempt is scheduled no more than 3600 seconds later

### Requirement: Retry window ends retries
The system SHALL stop retrying when the next attempt would start at or after the delivery's retry window end, and mark the delivery `failed` (dead letter). A delivery whose window has already ended when its job runs MUST be marked `failed` without a new attempt.

#### Scenario: Window ends after a failure
- **WHEN** an attempt fails with `500` and the computed next attempt is after the window end
- **THEN** the attempt is stored and the delivery is `failed`

#### Scenario: Window already ended
- **WHEN** the job of a pending delivery runs after its window ended
- **THEN** the delivery is `failed`, no request is sent and no attempt is stored

### Requirement: URL policy checked before every request
The system SHALL check the endpoint URL against the URL policy before every request. A URL that resolves to a non-public address MUST fail the delivery with an attempt that records the reason and no request sent; a DNS resolution failure MUST be retried.

#### Scenario: Host now resolves to a private address
- **WHEN** an endpoint's host resolves to `10.0.0.5` when its delivery runs
- **THEN** no request is sent, an attempt is stored with an error starting with `url_rejected`, and the delivery is `failed`

### Requirement: Attempts are append-only
The system SHALL store every attempt as a row with its delivery, number (1, 2, …), start time, duration, URL, request headers with the signature redacted, response status, the first 4 KB of the response body and the error. The database MUST reject any `UPDATE` of an attempt, and any `DELETE` unless the transaction set `courier.retention` to `on`.

#### Scenario: Attempt recorded
- **WHEN** an endpoint answers `500` with a body of 10 KB
- **THEN** the attempt stores number 1, status `500`, the first 4096 bytes of the body, a duration, and request headers whose `webhook-signature` is `[redacted]`

#### Scenario: Update rejected
- **WHEN** any code updates an attempt row
- **THEN** the database raises an error and the row is unchanged

#### Scenario: Delete rejected outside retention
- **WHEN** any code deletes an attempt row without setting `courier.retention`
- **THEN** the database raises an error and the row still exists

#### Scenario: Delete allowed for retention
- **WHEN** a transaction runs `SET LOCAL courier.retention = on` and deletes an attempt row
- **THEN** the row is deleted

### Requirement: Delivery status only moves forward
The system SHALL change a delivery's status only from `pending` to `succeeded` or `failed`. A result recorded for a delivery that is no longer `pending` MUST store no attempt and change nothing.

#### Scenario: Late result ignored
- **WHEN** a result is recorded for a delivery that is already `succeeded`
- **THEN** no attempt is stored and the delivery is unchanged

### Requirement: One queue per endpoint
The system SHALL run each endpoint's deliveries in its own Oban queue `endpoint:<id>` limited to the endpoint's `max_concurrency`. Queues of enabled endpoints MUST be started at boot; creating or enabling an endpoint starts its queue, changing `max_concurrency` scales it, and disabling it stops it.

#### Scenario: Queues started at boot
- **WHEN** the queue manager starts with two enabled endpoints and one disabled endpoint
- **THEN** it starts exactly the two enabled endpoints' queues with their limits

#### Scenario: Queue follows endpoint changes
- **WHEN** an endpoint is created, its `max_concurrency` changed to 5, and then it is disabled
- **THEN** its queue is started with limit 10, scaled to 5, and stopped

#### Scenario: Job in the endpoint's queue
- **WHEN** an event creates a pending delivery for an endpoint
- **THEN** a delivery job for it exists in the queue `endpoint:<endpoint id>`

### Requirement: Read a delivery with its attempts
The system SHALL let a key with the `read` scope get `GET /api/v1/deliveries/:id` with the delivery's status, attempt count, next attempt time, window end, completion time and its attempts in order, without request headers. An unknown or malformed id MUST get `404`.

#### Scenario: Delivery with attempts
- **WHEN** an operator requests a delivery that failed once and then succeeded
- **THEN** the response is `200` with status `succeeded` and two attempts numbered 1 and 2

#### Scenario: Unknown delivery
- **WHEN** an operator requests a delivery id that does not exist or is malformed
- **THEN** the response is `404` with code `not_found`

### Requirement: Bounded response reading
The system SHALL stop reading a response body after its first 4096 bytes, and SHALL end any request that has not completed within 30 seconds, from connect to the end of reading, recording it as a timeout that is retried like any other.

#### Scenario: Large response body
- **WHEN** an endpoint answers `200` with a 10 MB body sent in chunks
- **THEN** the client stops reading after the first 4096 bytes, closes the connection before the endpoint has sent the whole body, and returns status `200` with those 4096 bytes

#### Scenario: Body that trickles in
- **WHEN** an endpoint sends its status and one byte of body and then nothing more
- **THEN** the request ends at the deadline with error `timeout`

### Requirement: Delivery dependencies outlive delivery jobs
The system SHALL start the HTTP connection pool and the supervisor of webhook requests before the job processor, and SHALL stop them only after it, so no delivery job runs while they are unavailable.

#### Scenario: Supervision order
- **WHEN** the application has started
- **THEN** `Courier.Finch` and `Courier.Delivery.TaskSupervisor` were started before Oban, and Oban before `Courier.Delivery.QueueManager`

### Requirement: Expired pending deliveries are swept
The system SHALL, at least every 5 minutes, mark `failed` without a new attempt every `pending` delivery whose retry window has ended, and cancel its delivery job, including deliveries of disabled endpoints whose queues are stopped.

#### Scenario: Delivery of a disabled endpoint expires
- **WHEN** an endpoint is disabled with a pending delivery and the delivery's window then ends
- **THEN** the next sweep marks the delivery `failed` with `completed_at` set, stores no attempt and cancels its job

#### Scenario: Pending delivery inside its window is kept
- **WHEN** the sweep runs and a pending delivery's window has not ended
- **THEN** the delivery stays `pending` and its job is untouched
