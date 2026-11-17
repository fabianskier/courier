# Proposal

## Why

Operators increasingly ask an AI agent "why did this webhook fail?" instead of opening a dashboard. courier should answer that from Claude Code or Claude Desktop with the same data and rules as its API (FR-29 to FR-32), and it is the last piece of the backend before the frontend work.

## What Changes

- **MCP endpoint**: `POST /mcp` (Streamable HTTP, `anubis_mcp` 2.2, as decided in the MCP ADR), inside the Phoenix app and authenticated with the existing API keys: `read` scope to connect, `write` scope for the mutating tool.
- **Read-only tools**: `get_event`, `get_delivery` (with attempts and resends), `list_deliveries` (filters, limit, cursor), `list_failed_deliveries` and `get_endpoint_health`.
- **One mutating tool**: `resend_delivery`, refused without the `write` scope; its description says it changes state. It calls `Courier.Delivery.resend/2` with the actor `api_key:<key name>`, like the API.
- **Untrusted data**: event payloads and response bodies are returned truncated and wrapped as untrusted data, never as plain text the agent could read as instructions.
- **Call log**: one `info` log line per tool call with the tool, the key name, the arguments and the result status; never tokens, payloads or bodies.
- **Context**: new `Courier.Delivery.list_deliveries/1` (filters and keyset pagination) and `Courier.Delivery.count_by_status/1`, which the dashboard will also use.
- **Docs**: an "MCP server" section in `docs/architecture.md` and how to connect Claude Code in the README, with an example call per tool.
- **Not in this change**: resources and prompts, a REST `GET /api/v1/deliveries` (step 10), a stored call log, and stdio transport.

## Capabilities

### New Capabilities
- `mcp-server`: the MCP endpoint, its authentication, the six tools, untrusted-data marking and the call log.

### Modified Capabilities
None.

## Impact

- New dependency `anubis_mcp ~> 2.2` (brings `peri`; `finch`, `plug` and `telemetry` are already in the project). Checked on 2026-11-16: 2.2.0 is the latest release.
- New `lib/courier_mcp/` (`CourierMCP.Server`, one module per tool, shared helpers), a route and a supervised server process; two new functions in `Courier.Delivery`.
- No database changes. Existing tests are not modified.
- If the library turns out to be a poor fit in task 1.1, the task stops and reports it: the ADR's fallback (a hand-written JSON-RPC handler) needs a new ADR, not a silent switch.
