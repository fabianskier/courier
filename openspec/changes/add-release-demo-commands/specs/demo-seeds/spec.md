# Spec Delta

## ADDED Requirements

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
