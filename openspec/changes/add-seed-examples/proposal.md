# Proposal

## Why

After `bin/seed`, a demo user has the token and the merchant ids but only one ready command (the simulator). Every other demo step (sign in to the dashboard, the load test, watching the receiver, the API, connecting Claude Code over MCP) needs the token and ids typed in by hand, which is where demos go wrong.

## What Changes

- The seeding output ends with a "Try it" block of ready-to-run examples using the new token and ids: the dashboard URL to sign in with the key, a load test against the fast merchant, the receiver log (Docker only), a `curl` for failed deliveries, and the `claude mcp add` command for the MCP server.
- Mix and release outputs name their own commands (`mix courier.load` vs `docker compose exec courier bin/load`).
- **Not in this change**: printing signing secrets (never), or examples for a database that was already seeded (no token is shown then).

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `demo-seeds`: the seeding output adds the ready-to-run examples.

## Impact

- `CourierDemo.Seeds.report/2` only; a new test file. No data or behaviour changes.
