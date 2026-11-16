# Spec Delta

## ADDED Requirements

### Requirement: Endpoint health is visible
The system SHALL include in every endpoint response its `consecutive_failures`, `degraded` (true when marked degraded) and `degraded_at`, and SHALL let `GET /api/v1/endpoints` filter with `degraded=true` or `degraded=false`.

#### Scenario: Health in the response
- **WHEN** an operator reads an endpoint with 2 consecutive failures that is not degraded
- **THEN** the response has `consecutive_failures` 2, `degraded` false and `degraded_at` null

#### Scenario: List degraded endpoints
- **WHEN** an operator lists endpoints with `degraded=true`
- **THEN** only degraded endpoints are returned
