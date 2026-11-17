# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected. Read design.md before each task.

## 1. Endpoint and first tool

- [x] 1.1 Add `anubis_mcp ~> 2.2` to `mix.exs`, `CourierMCP.Server`, its child in `Courier.Application`, the `/mcp` route behind `Authenticate` and the `read` scope, `CourierMCP.Call`, `CourierMCP.Untrusted`, `CourierMCP.Views` (event part) and the `get_event` tool, plus `test/support/mcp_client.ex` (JSON-RPC over `ConnCase`: `initialize`, `tools/list`, `tools/call`); verify with new tests in `test/courier_mcp/endpoint_test.exs` ("Scenario: Missing key rejected", "Scenario: Key without read rejected", "Scenario: Session initialized") and `test/courier_mcp/get_event_test.exs` ("Scenario: Event returned", "Scenario: Unknown event", "Scenario: Payload marked untrusted", "Scenario: Long payload truncated"), and a test that a tool sees the key of the current request when a session opened with another key is reused; if the library cannot do this, stop and report instead of working around it

## 2. Read tools

- [x] 2.1 Add `Courier.Delivery.list_deliveries/1` and `Courier.Delivery.count_by_status/1` as in design.md; verify with new tests in `test/courier/delivery_list_test.exs` (filters by status, endpoint and event, newest first, limit and cursor, invalid cursor, counts per status)
- [x] 2.2 Add the `get_delivery`, `list_deliveries` and `list_failed_deliveries` tools with their views; verify with new tests in `test/courier_mcp/delivery_tools_test.exs`: "Scenario: Delivery with attempts", "Scenario: Unknown delivery", "Scenario: Filtered by status", "Scenario: Pages follow the cursor", "Scenario: Limit above the maximum rejected", "Scenario: Invalid cursor" and "Scenario: Only failed deliveries"
- [ ] 2.3 Add the `get_endpoint_health` tool; verify with new tests in `test/courier_mcp/endpoint_health_test.exs`: "Scenario: Degraded endpoint" and "Scenario: Unknown endpoint"

## 3. Resend and audit

- [ ] 3.1 Add the `resend_delivery` tool (write scope checked in the tool, actor `api_key:<key name>`, annotations and description as in design.md); verify with new tests in `test/courier_mcp/resend_test.exs`: "Scenario: Resent with a write key", "Scenario: Read key refused", "Scenario: Pending delivery refused" and "Scenario: Tools listed"
- [ ] 3.2 Verify the call log with new tests in `test/courier_mcp/call_log_test.exs` (with `CourierWeb.LogCapture.capture_debug_log/1`): "Scenario: Call logged", "Scenario: Failed call logged" and "Scenario: Log without secrets"; then add an "MCP server" section to `docs/architecture.md` (endpoint, auth, the tool table, untrusted data, call log, how to connect Claude Code with `claude mcp add --transport http`), replace the MCP line of "Security notes" with the implemented behaviour, add a "Use it from Claude Code" section to `README.md` with one example question per tool, and mark step 8 done in `docs/roadmap.md` with the frontend bootstrap (step 9) as next; verify `sh .smelt/checks.sh` and `openspec validate add-mcp-server --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-mcp-server <task>` and review before merging.
- After the last merge, connect Claude Code to the Docker demo (`claude mcp add --transport http courier http://localhost:4000/mcp --header "Authorization: Bearer <demo key>"`), ask why a delivery failed and resend it, then archive.
