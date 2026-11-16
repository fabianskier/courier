# event-simulator Specification

## Purpose

A command-line producer that sends events to courier's ingestion API at a steady rate, with a share of exact repeats, so demos and load checks exercise ingestion, idempotency and delivery with realistic traffic.

## Requirements

### Requirement: Simulator options
`mix courier.simulate` SHALL take `--merchant ID` (required, repeatable), `--token` (default `COURIER_INGEST_TOKEN`; required), `--url` (default `http://localhost:4000`), `--count` (default 100, at least 1), `--rate` events per second (default 5, 1 to 1000), `--repeat-share` (default 0.1, from 0 to 1) and `--types` (comma-separated). Missing or invalid options MUST print what is wrong and exit with status 1 without sending anything.

#### Scenario: Missing merchant
- **WHEN** the simulator runs with a token but no `--merchant`
- **THEN** it prints that a merchant is required, sends no request and exits with status 1

#### Scenario: Invalid rate
- **WHEN** the simulator runs with `--rate 0`
- **THEN** it prints that the rate must be between 1 and 1000, sends no request and exits with status 1

### Requirement: Event requests
The simulator SHALL send `--count` requests to `POST <url>/api/v1/events` with the token as a Bearer key, each with a JSON body holding a `type` from `--types`, a `merchant_id` from `--merchant` and an object `payload` made up by the simulator, and a fresh `Idempotency-Key` for each new event. It MUST NOT send more than `--rate` requests in any one-second window on average over the run.

#### Scenario: New events sent
- **WHEN** the simulator runs with `--count 5 --repeat-share 0` against a stubbed API
- **THEN** the stub receives 5 authenticated `POST /api/v1/events` requests with 5 distinct idempotency keys, each with a type from the list and a listed merchant

#### Scenario: Rate respected
- **WHEN** the simulator runs with `--count 10 --rate 20`
- **THEN** the run takes at least 450 ms

### Requirement: Repeated requests
The simulator SHALL make about `--repeat-share` of the requests repeats: an earlier request sent again with the same idempotency key and the same body, byte for byte. The first request is never a repeat.

#### Scenario: Repeats reuse key and body
- **WHEN** the simulator runs with `--count 20 --repeat-share 0.5`
- **THEN** at least one request repeats the idempotency key of an earlier one, and every repeated request has exactly the body of the first request with that key

#### Scenario: No repeats
- **WHEN** the simulator runs with `--repeat-share 0`
- **THEN** every request has a distinct idempotency key

### Requirement: Run summary
When the run ends the simulator SHALL print how many requests were answered `202` (new), `200` (repeats), with any other status (grouped by status) and how many failed without a response, and exit with status 0. It MUST NOT print the token.

#### Scenario: Summary printed
- **WHEN** a run gets three `202`, one `200`, one `422` and one connection error
- **THEN** the output says 3 new, 1 repeat, 1 rejected with status 422 and 1 failed, and does not contain the token
