# Spec Delta

## Purpose

Lets anyone check courier's performance targets on their own machine: a command sends events at a chosen rate and reports ingestion latency, time to first attempt and delivery throughput for that run.

## ADDED Requirements

### Requirement: Load options
The load command SHALL take an `ingest` API key (`--token` or `COURIER_INGEST_TOKEN`), one or more `--merchant` ids, `--rate` (events per second, default 50), `--count` (events, default 500), `--url` (default `http://localhost:4000`) and `--wait` (seconds to wait for first attempts, default 30). A missing token or merchant, or a rate, count or wait that is not a positive integer, MUST print an error and exit with a non-zero status without sending anything.

#### Scenario: Missing token
- **WHEN** the load command runs without `--token` and without `COURIER_INGEST_TOKEN`
- **THEN** it prints an error naming the token, sends no request and exits with a non-zero status

#### Scenario: Invalid rate
- **WHEN** the load command runs with `--rate 0`
- **THEN** it prints an error naming `--rate`, sends no request and exits with a non-zero status

### Requirement: Ingestion report
The load command SHALL send `--count` distinct events at `--rate` events per second, never retrying, and report the number sent, the achieved rate, the count per response status, requests without a response, and the client latency p50, p95 and p99 in milliseconds.

#### Scenario: Ingestion measured
- **WHEN** the command sends 100 events at 50 per second and every request answers `202`
- **THEN** the report shows 100 sent, 100 with status `202`, an achieved rate, and latency p50, p95 and p99

#### Scenario: Percentiles
- **WHEN** the measured latencies are 1 to 100 ms, one each
- **THEN** p50 is 50 ms, p95 is 95 ms and p99 is 99 ms

### Requirement: Delivery report
After sending, the load command SHALL wait up to `--wait` seconds for the deliveries created during the run to get their first attempt, then report the time to first attempt (first attempt start minus delivery creation) p50 and p95 overall and per endpoint, the attempts per second between the run's start and the report, and how many of the run's deliveries had no attempt yet. Skipped deliveries MUST NOT count.

#### Scenario: Time to first attempt
- **WHEN** a run creates deliveries whose first attempts started 100, 200 and 300 ms after creation
- **THEN** the report shows a time to first attempt p50 of 200 ms and p95 of 300 ms

#### Scenario: Per endpoint
- **WHEN** a run's deliveries go to two endpoints, one fast and one timing out
- **THEN** the report shows each endpoint's URL with its own time to first attempt and attempt count

#### Scenario: Deliveries without attempts
- **WHEN** the wait ends while 4 of the run's deliveries have no attempt
- **THEN** the report says 4 deliveries had no attempt yet and computes the times from the others

### Requirement: Release load command
The release SHALL include `bin/load` with the same options and report as `mix courier.load`, reading delivery timings from the database without starting the rest of the application, so it can run inside the running `courier` container.

#### Scenario: Load from the release
- **WHEN** an operator runs `docker compose exec courier bin/load --token <key> --merchant <id> --count 100`
- **THEN** the events are sent to the running courier and the ingestion and delivery reports are printed
