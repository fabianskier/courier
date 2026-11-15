# Design

## Context

Ecto logs each query through `Logger` at `debug` (the repo's default `log: :debug`), including the query parameters as cast by Ecto. For `Courier.Encrypted.Binary` fields the cast value is the plaintext; encryption happens when the value is dumped, after the log entry is built. `redact: true` on the schema field only affects `inspect/1`, not query logs. The two writes that carry secrets are `Repo.insert/2` in `Courier.Endpoints.create_endpoint/1` and `Repo.update/2` in `Courier.Endpoints.rotate_secret/2`. `update_endpoint/2` never changes secrets, and reads do not log returned rows.

## Goals / Non-Goals

**Goals:** no secret in any log, with the smallest change that keeps other query logs intact.

**Non-Goals:** filtering parameters in every query log, or changing log levels per environment.

## Decisions

- Pass `log: false` to the two repo calls that write secrets. Ecto then emits no log entry for them; telemetry events still fire for metrics.
- Alternatives considered:
  - `config :courier, Courier.Repo, log: false` (or a higher level) in dev: hides every query, which makes development harder, and does not protect someone who raises the level elsewhere.
  - A custom Ecto logger that scrubs parameters: more code to maintain for two call sites.
- `docs/architecture.md` gains the rule: any repo call that writes a secret column passes `log: false`.

## Risks / Trade-offs

- [A future write of a secret forgets `log: false`] → The documented rule and the new tests on create and rotate; a later change that adds a secret write must add its own test.
