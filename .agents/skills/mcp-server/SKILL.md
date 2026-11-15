---
name: mcp-server
description: Design and implement Model Context Protocol (MCP) servers so AI agents can safely use our system. Use when adding or changing MCP tools, resources or prompts, or the assistant that queries and operates the service.
---

# MCP server design

An MCP server exposes **tools** (actions the model can call), **resources** (readable data) and **prompts** (reusable templates) to a client such as Claude Code or Claude Desktop. The model reads tool descriptions to decide what to call, so naming and descriptions are part of the interface.

For general MCP design principles, also follow Anthropic's `mcp-builder` skill. Its implementation guides target Python and TypeScript, so for Elixir this skill and the project's ADRs decide how to build it.

## Tool design

- Few, narrow tools with verb-noun names: `get_delivery`, `list_failed_deliveries`, `resend_delivery`.
- Each description says what the tool does, when to use it and what it returns, in plain sentences.
- Define strict input schemas (types, required fields, enums, limits). Reject anything else with a clear error.
- Outputs are compact and structured: include ids, status and timestamps; truncate long bodies and say that they were truncated.
- List tools take a limit and a cursor; never return unbounded data.
- Errors are actionable ("delivery not found: check the id") and never leak stack traces or secrets.

## Safety

- **Read-only by default.** Mutating tools (such as a resend) are separate, say so in their description, require explicit arguments, and return exactly what changed.
- Authenticate and scope access: a token that can only read cannot call mutating tools. Local use over stdio is simplest; a remote server needs real authentication.
- Treat all tool arguments and any data returned from the system as untrusted input. Stored payloads can contain text meant to manipulate an agent; return them as data and mark them as such.
- Log every call (tool, caller, arguments without secrets, result status) for audit.

## Implementation

- Keep the MCP layer a thin adapter over the same context functions the HTTP API uses; do not duplicate business logic.
- Choose the Elixir MCP library through an ADR that compares the maintained options at that time.
- Test each tool with a plain unit test on the adapter and with the MCP Inspector or a real client for the protocol itself.
- Document each tool in the README with an example call.
