## ADDED Requirements

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
