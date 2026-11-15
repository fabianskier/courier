# Spec Delta

## ADDED Requirements

### Requirement: Signing secrets never appear in logs
The system MUST NOT write an endpoint's current or previous signing secret to the logs at any log level, including database query logs, when creating an endpoint or rotating its secret.

#### Scenario: Creating an endpoint logs no secret
- **WHEN** an endpoint is created through the API while logs are captured at `debug` level
- **THEN** the captured logs do not contain the returned secret or its base64 part

#### Scenario: Rotating a secret logs no secret
- **WHEN** an endpoint's secret is rotated through the API while logs are captured at `debug` level
- **THEN** the captured logs contain neither the new secret nor the previous one
