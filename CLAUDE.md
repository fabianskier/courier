# courier

A webhook delivery engine in Elixir with a React + shadcn/ui dashboard and an MCP server. Public portfolio project.

- Overview: `README.md`. Requirements: `docs/analysis.md`. Design: `docs/architecture.md`. Rationale: `docs/decisions.md`. Status and next steps: `docs/roadmap.md`. Workflow and Smelt: `docs/development.md`.
- Code, docs and OpenSpec artifacts are written in English; conversation may be in Spanish.
- Changes follow OpenSpec (`openspec/`): propose → apply → archive. Run `openspec validate --strict` before building. Implement only the task you were given from the change's `tasks.md`, and mark its checkbox when done.
- Follow the accepted ADRs in `docs/decisions.md`. If a change needs a different choice, propose a new ADR; never rewrite an accepted one.
- Keep all domain logic in contexts under `lib/courier/`. `lib/courier_web/` (JSON API, channels) and `lib/courier_mcp/` stay thin adapters.
- Tests: name them after the spec (`describe "Requirement: <name>"`, `test "Scenario: <name>"`). Never modify or delete an existing test; add new test files.
- Never log or store secrets, full signatures or `Authorization` headers.
- Before finishing, run `mix precommit` and `sh .smelt/checks.sh`, and fix any failure.

## Git

- Use Conventional Commits: `type(scope): description` in English, imperative mood, lowercase, no trailing period.
  Types: feat, fix, refactor, test, docs, chore, ci, perf, build.
- Do not add `Co-Authored-By` trailers or any Claude/Anthropic attribution to commits or pull requests.
- Only commit or push when explicitly asked.
