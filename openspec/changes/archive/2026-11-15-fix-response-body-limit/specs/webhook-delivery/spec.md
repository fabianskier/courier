# Spec Delta

## ADDED Requirements

### Requirement: Bounded response reading
The system SHALL stop reading a response body after its first 4096 bytes, and SHALL end any request that has not completed within 30 seconds, from connect to the end of reading, recording it as a timeout that is retried like any other.

#### Scenario: Large response body
- **WHEN** an endpoint answers `200` with a 10 MB body sent in chunks
- **THEN** the client stops reading after the first 4096 bytes, closes the connection before the endpoint has sent the whole body, and returns status `200` with those 4096 bytes

#### Scenario: Body that trickles in
- **WHEN** an endpoint sends its status and one byte of body and then nothing more
- **THEN** the request ends at the deadline with error `timeout`
