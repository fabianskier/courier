# demo-seeds Specification

## Purpose

A demo data set created with one command: an API key, merchants and endpoints wired to the demo receiver's behaviours, so a demo shows successes, retries, dead letters, skipped deliveries and a slow endpoint without manual setup.

## Requirements

### Requirement: Demo data set
Seeding SHALL create an API key named `demo` with the scopes `ingest`, `read` and `write`, and three merchants with five enabled endpoints at `<receiver URL>/hooks/<name>/<behaviour>`: one each for `ok`, `fail`, `rate-limit`, `bad-request` and `timeout`. The `ok` endpoint MUST filter to `payment.*`, the `fail` endpoint MUST have a retry window of 300 seconds, and the `timeout` endpoint MUST have a `max_concurrency` of 2.

#### Scenario: Data created
- **WHEN** seeding runs on an empty database
- **THEN** a `demo` key with `ingest`, `read` and `write` exists, three merchants exist, and their five endpoints point at the receiver's `ok`, `fail`, `rate-limit`, `bad-request` and `timeout` paths with the filter, retry window and concurrency above

### Requirement: Receiver URL
The receiver URL used for the endpoints and the secret registrations SHALL be `http://localhost:4001` by default, and the value of `COURIER_DEMO_RECEIVER_URL` when it is set.

#### Scenario: Receiver URL from the environment
- **WHEN** seeding runs with the receiver URL set to `https://receiver.public.test`
- **THEN** every endpoint URL starts with `https://receiver.public.test/hooks/`

### Requirement: Secrets registered with the receiver
Seeding SHALL register each endpoint's signing secret with the receiver under the endpoint's name (`PUT <receiver URL>/_secrets/<name>`). When the receiver cannot be reached or rejects a secret, seeding MUST still create the data, warn that those endpoints' requests will be answered unchecked, and not print the secrets.

#### Scenario: Secrets registered
- **WHEN** seeding runs with a reachable receiver
- **THEN** the receiver gets one registration per endpoint, each with that endpoint's current secret

#### Scenario: Receiver unreachable
- **WHEN** seeding runs and the receiver refuses connections
- **THEN** the data is created, the output warns that signatures will be unchecked, and the output contains no `whsec_` secret

### Requirement: Seeding output
Seeding SHALL print the `demo` key's token once, the merchant names and ids, and a `mix courier.simulate` command with those merchant ids that can be run as printed.

#### Scenario: Output ready to use
- **WHEN** seeding finishes
- **THEN** the output contains the token, each merchant id and a `mix courier.simulate` command with a `--merchant` option for each merchant

### Requirement: Seed once
Seeding SHALL refuse to run when an API key named `demo` already exists: it MUST create nothing, print that the database is already seeded and how to reset it, and leave existing data unchanged.

#### Scenario: Second run refused
- **WHEN** seeding runs a second time on the same database
- **THEN** no merchant, endpoint or key is added and the output says the database is already seeded and to run `mix ecto.reset`

### Requirement: Release seeding command
The release SHALL provide a `bin/seed` command that runs the seeding in the running release, with the same data set, secret registration with the receiver and refusal to seed twice as the Mix seeds. It MUST NOT print a signing secret.

#### Scenario: Release receiver unreachable
- **WHEN** the release seeding runs and the receiver refuses connections
- **THEN** the data is created and the output warns that signatures will be unchecked, without a `whsec_` secret and without mentioning `mix`

### Requirement: Release seeding output
The release seeding output SHALL name commands that work in the Docker demo instead of the Mix ones: a `docker compose exec courier bin/simulate` command with the token and a `--merchant` option for each merchant, and, when the database is already seeded, how to start again from an empty database with Docker Compose.

#### Scenario: Release output ready to use
- **WHEN** the release seeding runs on an empty database with a reachable receiver
- **THEN** the output contains the token, each merchant id and a `docker compose exec courier bin/simulate` command with a `--merchant` option for each merchant, and it contains neither `mix ` nor a `whsec_` secret

#### Scenario: Release second run refused
- **WHEN** the release seeding runs a second time on the same database
- **THEN** no merchant, endpoint or key is added and the output says the database is already seeded and to run `docker compose down -v`, without mentioning `mix ecto.reset`

### Requirement: Ready-to-run demo examples
After creating the demo data, the seeding output SHALL end with ready-to-run examples using the new token and ids: the dashboard URL, a load test against the fast merchant, a `curl` for failed deliveries and a `claude mcp add` command for the MCP server. Release examples MUST be Docker Compose commands (plus the receiver's log); Mix examples MUST use `mix courier.load`. No signing secret is printed.

#### Scenario: Examples after seeding
- **WHEN** seeding finishes
- **THEN** the output ends with the dashboard URL, a load command with the token and the fast merchant's id, a `curl` with the token, and a `claude mcp add` command with the token

#### Scenario: Release examples
- **WHEN** the release seeding finishes
- **THEN** the examples use `docker compose exec courier bin/load` and include `docker compose logs -f demo-receiver`

#### Scenario: Mix examples
- **WHEN** the Mix seeding finishes
- **THEN** the load example uses `mix courier.load` and no Docker command appears
