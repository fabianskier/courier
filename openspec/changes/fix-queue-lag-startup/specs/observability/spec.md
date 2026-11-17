# Spec Delta

## ADDED Requirements

### Requirement: Queue lag measured with the database up
The system SHALL start the periodic measurements, including the queue lag, after the database repository, and SHALL stop them before it, so no measurement runs while the repository is unavailable.

#### Scenario: Telemetry starts after the repo
- **WHEN** the application has started
- **THEN** `Courier.Repo` was started before `CourierWeb.Telemetry`
