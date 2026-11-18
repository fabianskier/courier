# Spec Delta

## Purpose

Keeps the dashboard current without reloads: courier pushes small change notices over an authenticated socket, and the dashboard refetches the affected data over REST within 5 seconds of a change.

## ADDED Requirements

### Requirement: Change notices
The system SHALL broadcast a notice after every committed change the dashboard shows: `event_ingested` for a new event, `delivery_changed` when a delivery is created, gets a retry scheduled, succeeds, fails or is created by a resend, `endpoint_changed` when an endpoint is created, updated, has its secret rotated, turns degraded or recovers, and `merchant_changed` when a merchant is created or updated. A change that is rolled back MUST NOT be announced.

#### Scenario: Ingestion announced
- **WHEN** an event is accepted and fans out to two endpoints
- **THEN** one `event_ingested` notice and one `delivery_changed` notice per delivery are broadcast, with status `pending` or `skipped`

#### Scenario: Delivery outcome announced
- **WHEN** a delivery's attempt succeeds
- **THEN** a `delivery_changed` notice with status `succeeded` is broadcast after the attempt is stored

#### Scenario: Resend announced
- **WHEN** a delivery is resent
- **THEN** a `delivery_changed` notice for the new delivery with status `pending` is broadcast

#### Scenario: Endpoint changes announced
- **WHEN** an endpoint is updated, its secret rotated, or it turns degraded
- **THEN** an `endpoint_changed` notice with its id and merchant id is broadcast each time

#### Scenario: Rejected change not announced
- **WHEN** an event is rejected as invalid, or a repeat is answered with the original event
- **THEN** no notice is broadcast

### Requirement: Notices carry ids only
Notices SHALL carry only ids, a status or a type: `event_ingested` the event id, merchant id and type; `delivery_changed` the delivery id, event id, endpoint id and status; `endpoint_changed` the endpoint id and merchant id; `merchant_changed` the merchant id. They MUST NOT carry payloads, response bodies, URLs, secrets or tokens.

#### Scenario: Notice contents
- **WHEN** a delivery of an event with a payload fails with a response body
- **THEN** the `delivery_changed` notice holds exactly its id, event id, endpoint id and status

### Requirement: Authenticated dashboard socket
The system SHALL accept dashboard sockets at `/socket` only with a valid API key that has the `read` scope, given as the WebSocket auth token, never as a URL parameter. A missing, unknown, revoked or read-less key MUST be refused. An open socket whose key is revoked MUST be closed within 60 seconds, also when the key is revoked from another process (`mix courier.keys.revoke`).

#### Scenario: Socket with a read key
- **WHEN** a client connects with a valid key that has the `read` scope
- **THEN** the socket is accepted

#### Scenario: Socket refused
- **WHEN** a client connects without a key, with an unknown key, or with a key that has only the `ingest` scope
- **THEN** the socket is refused

#### Scenario: Revoked key disconnected
- **WHEN** a key with an open socket is revoked
- **THEN** that socket is closed at its next key check, at most 60 seconds later

### Requirement: Dashboard topics
The dashboard channel SHALL offer the topics `dashboard:events`, `dashboard:deliveries`, `dashboard:endpoints` and `dashboard:merchants`, and push each notice to the topic of its resource: `event_ingested` to `dashboard:events`, `delivery_changed` to `dashboard:deliveries`, `endpoint_changed` to `dashboard:endpoints` and `merchant_changed` to `dashboard:merchants`. Joining any other topic MUST be refused.

#### Scenario: Notice pushed to its topic
- **WHEN** a client joined to `dashboard:deliveries` and a delivery fails
- **THEN** the client receives `delivery_changed` with the delivery's id and status `failed`

#### Scenario: Unknown topic refused
- **WHEN** a client joins `dashboard:api_keys`
- **THEN** the join is refused

### Requirement: Dashboard refreshes from notices
While signed in, the dashboard SHALL join the four topics and refetch the data a notice affects: lists and the detail of the changed resource, and the lookups for endpoints and merchants. Bursts of notices MUST be coalesced so each affected list is refetched at most about once per second, and the refetch MUST start within 5 seconds of the notice. On sign-out the socket MUST be closed.

#### Scenario: Failed delivery appears
- **WHEN** the operator is on the failed view and a `delivery_changed` notice with status `failed` arrives
- **THEN** the failed list is refetched within 5 seconds and shows the delivery without a reload

#### Scenario: Open delivery refreshed
- **WHEN** the operator is on a delivery's page and a `delivery_changed` notice for that delivery arrives
- **THEN** the delivery is refetched and its new status and attempts are shown

#### Scenario: Burst coalesced
- **WHEN** 200 `delivery_changed` notices arrive within one second
- **THEN** the deliveries list is refetched at most twice

#### Scenario: Socket closed on sign-out
- **WHEN** the operator signs out
- **THEN** the dashboard socket is closed

### Requirement: Reconnect and live status
The dashboard SHALL show whether updates are live or reconnecting, reconnect automatically when the socket drops, and refetch every active query after a reconnect, so notices missed while disconnected do not leave stale data.

#### Scenario: Reconnect refetches
- **WHEN** the socket drops and reconnects
- **THEN** the status shows "Reconnecting" while it is down and "Live" again after, and every active query is refetched once
