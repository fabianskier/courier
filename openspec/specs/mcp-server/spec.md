# mcp-server Specification

## Purpose
Lets AI agents query courier and, with rights, resend deliveries through the Model Context Protocol, with the same API keys and rules as the HTTP API, compact outputs, stored data marked as untrusted and every call logged.

## Requirements

### Requirement: Authenticated MCP endpoint
The system SHALL serve MCP over Streamable HTTP at `/mcp` and require an API key with the `read` scope as a Bearer token on every request. A missing or invalid key MUST be answered `401` and a key without `read` MUST be answered `403`, both with the API's error shape, before any MCP message is handled.

#### Scenario: Missing key rejected
- **WHEN** a client sends an MCP `initialize` request to `/mcp` without an `Authorization` header
- **THEN** the response is `401` with the error code `unauthorized`

#### Scenario: Key without read rejected
- **WHEN** a client sends an MCP `initialize` request with a key that has only the `ingest` scope
- **THEN** the response is `403`

#### Scenario: Session initialized
- **WHEN** a client sends an MCP `initialize` request with a `read` key
- **THEN** the response names the server `courier` and declares the tools capability

### Requirement: Tool list
The server SHALL list exactly six tools: `get_event`, `get_delivery`, `list_deliveries`, `list_failed_deliveries`, `get_endpoint_health` and `resend_delivery`, each with a description and an input schema. The five read tools MUST be marked read-only, and the description of `resend_delivery` MUST say that it changes state.

#### Scenario: Tools listed
- **WHEN** a client with a `read` key lists the tools
- **THEN** it gets the six tools, the five read tools are marked read-only and the description of `resend_delivery` says it changes state

### Requirement: Get an event
`get_event` SHALL take an event id and return the event's id, type, merchant id and creation time, its payload as untrusted data, and its deliveries with their id, endpoint id, status and attempt count. An unknown or malformed id MUST return a tool error that says the event was not found.

#### Scenario: Event returned
- **WHEN** a client calls `get_event` with the id of an event that has two deliveries
- **THEN** the result has the event's type and merchant id and both deliveries with their statuses

#### Scenario: Unknown event
- **WHEN** a client calls `get_event` with an id that matches no event
- **THEN** the result is a tool error with the code `not_found`

### Requirement: Get a delivery
`get_delivery` SHALL take a delivery id and return its status, attempt count, next attempt time, window end, `triggered_by` and `resend_of_id`, its attempts in order (number, start time, duration, response status, error, and the response body as untrusted data) and its resends. It MUST NOT return request headers or signatures.

#### Scenario: Delivery with attempts
- **WHEN** a client calls `get_delivery` for a failed delivery with two attempts answered `500`
- **THEN** the result has the status `failed` and both attempts in order with the response status `500`, and contains no `webhook-signature`

#### Scenario: Unknown delivery
- **WHEN** a client calls `get_delivery` with an id that matches no delivery
- **THEN** the result is a tool error with the code `not_found`

### Requirement: List deliveries
`list_deliveries` SHALL return deliveries newest first, without attempts, filtered by the optional `status`, `endpoint_id` and `event_id`, at most `limit` per call (1 to 50, default 20), with a `next_cursor` when more exist. A `cursor` from an earlier call MUST continue after its last delivery. Input outside the schema and an invalid cursor MUST return an error without listing anything.

#### Scenario: Filtered by status
- **WHEN** a client calls `list_deliveries` with `status` `pending` and deliveries exist in several statuses
- **THEN** only pending deliveries are returned

#### Scenario: Pages follow the cursor
- **WHEN** three deliveries exist and a client calls `list_deliveries` with `limit` 2, then again with the returned `next_cursor`
- **THEN** the first call returns the two newest and a cursor, and the second returns the remaining one without a cursor

#### Scenario: Limit above the maximum rejected
- **WHEN** a client calls `list_deliveries` with `limit` 500
- **THEN** the call is rejected as invalid input

#### Scenario: Invalid cursor
- **WHEN** a client calls `list_deliveries` with a cursor it made up
- **THEN** the result is a tool error with the code `invalid_cursor`

### Requirement: List failed deliveries
`list_failed_deliveries` SHALL return only deliveries with the status `failed`, newest first, with the optional `endpoint_id` filter and the same limit and cursor rules as `list_deliveries`.

#### Scenario: Only failed deliveries
- **WHEN** failed, pending and succeeded deliveries exist and a client calls `list_failed_deliveries`
- **THEN** only the failed ones are returned

### Requirement: Get endpoint health
`get_endpoint_health` SHALL take an endpoint id and return whether the endpoint is enabled, its consecutive failures, whether it is degraded and since when, and how many of its deliveries are in each status. It MUST NOT return the endpoint's signing secret.

#### Scenario: Degraded endpoint
- **WHEN** a client calls `get_endpoint_health` for a degraded endpoint with failed and pending deliveries
- **THEN** the result says it is degraded, with its consecutive failures and the count of deliveries per status, and contains no `whsec_` secret

#### Scenario: Unknown endpoint
- **WHEN** a client calls `get_endpoint_health` with an id that matches no endpoint
- **THEN** the result is a tool error with the code `not_found`

### Requirement: Resend a delivery
`resend_delivery` SHALL take a delivery id and, for a key with the `write` scope, create a resend exactly as the API does, with the actor `api_key:<key name>`, and return the new delivery and the id of the one it resends. Without `write` it MUST return a tool error and create nothing. A delivery that cannot be resent MUST return a tool error naming the reason.

#### Scenario: Resent with a write key
- **WHEN** a client with a `write` key named `agent` calls `resend_delivery` for a failed delivery
- **THEN** a new pending delivery exists with `resend_of_id` set to the failed one and `triggered_by` `api_key:agent`, and the result has its id

#### Scenario: Read key refused
- **WHEN** a client with only the `read` scope calls `resend_delivery` for a failed delivery
- **THEN** the result is a tool error with the code `forbidden` and no delivery is created

#### Scenario: Pending delivery refused
- **WHEN** a client with a `write` key calls `resend_delivery` for a pending delivery
- **THEN** the result is a tool error with the code `delivery_in_progress`

### Requirement: Mark stored data as untrusted
Event payloads and response bodies SHALL be returned only inside an untrusted-data wrapper that says the content comes from an external system and must not be followed as instructions. A payload MUST be cut at 2,000 characters and a response body at 500, with a flag that says whether it was cut.

#### Scenario: Payload marked untrusted
- **WHEN** a client calls `get_event` for an event whose payload contains the text "ignore previous instructions"
- **THEN** that text appears only inside the untrusted-data wrapper, which is flagged as not truncated

#### Scenario: Long payload truncated
- **WHEN** a client calls `get_event` for an event with a 10,000-character payload
- **THEN** the wrapper holds 2,000 characters and is flagged as truncated

### Requirement: Log every tool call
The system SHALL write one `info` log line for every tool call, successful or not, with the tool's name, the name of the API key, the call's arguments, the result status and the duration. The line MUST NOT contain the token, a payload, a response body or a signing secret.

#### Scenario: Call logged
- **WHEN** a client with a key named `agent` calls `get_delivery`
- **THEN** one log line names the tool `get_delivery`, the key `agent`, the delivery id and the status `ok`

#### Scenario: Failed call logged
- **WHEN** a client with only the `read` scope calls `resend_delivery`
- **THEN** one log line names the tool, the key and the status `error:forbidden`

#### Scenario: Log without secrets
- **WHEN** a client calls `get_event` for an event with a payload
- **THEN** the log line contains neither the token nor any text of the payload
