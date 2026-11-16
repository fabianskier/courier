# Spec Delta

## ADDED Requirements

### Requirement: Delivery dependencies outlive delivery jobs
The system SHALL start the HTTP connection pool and the supervisor of webhook requests before the job processor, and SHALL stop them only after it, so no delivery job runs while they are unavailable.

#### Scenario: Supervision order
- **WHEN** the application has started
- **THEN** `Courier.Finch` and `Courier.Delivery.TaskSupervisor` were started before Oban, and Oban before `Courier.Delivery.QueueManager`
