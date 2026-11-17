# Spec Delta

## ADDED Requirements

### Requirement: Release simulator command
The release SHALL provide a `bin/simulate` command that takes the options of `mix courier.simulate`, with the same defaults, validation and messages, and sends the same requests, without Mix. It MUST print the run summary to standard output and exit with status 0; with missing or invalid options it MUST print what is wrong to standard error, send nothing and exit with status 1. It MUST NOT print the token.

#### Scenario: Release run prints the summary
- **WHEN** the release command runs with a token, a merchant, `--count 3` and `--repeat-share 0` against a stubbed API that answers `202`
- **THEN** the stub receives 3 requests, standard output says 3 requests were sent and 3 were new, the output does not contain the token and the status is 0

#### Scenario: Release run rejects invalid options
- **WHEN** the release command runs with a token but no `--merchant`
- **THEN** standard error says that a merchant is required, no request is sent and the status is 1

#### Scenario: Release run reads the token from the environment
- **WHEN** the release command runs without `--token` and `COURIER_INGEST_TOKEN` is set
- **THEN** the requests carry that token as a Bearer key
