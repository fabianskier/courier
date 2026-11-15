# courier

A reliable **webhook delivery engine** in Elixir, with a React + shadcn/ui dashboard and an MCP server so AI agents can query and operate it.

- Idempotent ingestion: a repeated `Idempotency-Key` returns the original event.
- At-least-once delivery, signed with [Standard Webhooks](https://www.standardwebhooks.com/) (HMAC-SHA256).
- Retries with exponential backoff, jitter and `Retry-After`, inside a retry window of up to 24 h; then a dead-letter state.
- One queue per endpoint, so a slow merchant never delays the others.
- Append-only audit trail of every attempt; manual resend that never rewrites history.
- MCP server: read-only tools by default, a separate tool for resends.

> **Status:** design phase. The analysis, architecture and decisions are written; implementation starts next. See [docs/roadmap.md](docs/roadmap.md).

## Documentation

| Document | Contents |
|---|---|
| [docs/analysis.md](docs/analysis.md) | Problem, requirements (FR-1…FR-41), non-functional targets, risks |
| [docs/architecture.md](docs/architecture.md) | Context, container and sequence diagrams, data model, API surface |
| [docs/decisions.md](docs/decisions.md) | Architecture decision records (ADRs) |
| [docs/roadmap.md](docs/roadmap.md) | Build path and current status |
| [docs/development.md](docs/development.md) | How the project is built: specs, agents and Smelt |

## How it is built

Requirements and decisions come first; then each change is specified with [OpenSpec](https://github.com/Fission-AI/OpenSpec) and implemented task by task by AI agents (Claude Code) through **Smelt**, the author's private, personal software factory built in Elixir/OTP. Smelt runs each task in its own git worktree, checks it with a deterministic gate (protected tests, small diffs, spec validation, compile, format and tests) and merges only after human approval. Smelt is not required to build or run courier.

More in [docs/development.md](docs/development.md), including what Smelt does today and what is still to come.

## Stack

Elixir, Phoenix (JSON API and Channels), Ecto, PostgreSQL, Oban, Req · React, TypeScript, Vite, TanStack Router and Query, Tailwind, shadcn/ui · MCP (`anubis_mcp`) · Docker Compose.

## License

Copyright (c) 2026 Oscar Fabián Cristaldo Guzmán. All rights reserved. The code is published for review only; see [LICENSE](LICENSE).
