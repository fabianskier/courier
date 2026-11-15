---
name: elixir-otp
description: Elixir, Phoenix, Ecto, Oban and OTP conventions for this project. Use when writing or reviewing Elixir code, background jobs, database access, supervision trees or ExUnit tests.
---

# Elixir and OTP conventions

## Structure

- Domain logic lives in contexts under `lib/<app>/`. The web layer (`lib/<app>_web/`) is thin: parse input, call a context, render output.
- Contexts expose a small public API; keep schemas and queries private to the context.
- Communicate between parts with PubSub or function calls through the context, not by reaching into another context's tables.

## Code style

- Pattern match in function heads; use `with` for happy-path chains and return tagged tuples (`{:ok, value}` / `{:error, reason}`).
- Use atoms or structs for error reasons, not free-form strings.
- Add `@spec` and `@moduledoc` to public modules and functions.
- Put external services behind a small module (for example `Courier.Delivery.Client`) so the HTTP details stay in one place.
- No `Process.sleep` in tests; use `assert_receive`, `start_supervised!` and explicit synchronization.

## Phoenix API

- Keep API routes in the `:api` pipeline, separate from any HTML routes (no CSRF or session there). Put the version in the path (`/api/v1/...`).
- Controllers call a context and return `{:ok, result}` or `{:error, reason}`; a `FallbackController` turns errors into responses, so actions stay short.
- Render changeset errors as one structured JSON `errors` object, and use consistent status codes and an error body shape across the API.
- Paginate every list endpoint with a limit and a cursor.
- Publish an OpenAPI document (for example with `open_api_spex`) so the frontend can generate types.

## HTTP clients (Req)

- Build one configured client with `Req.new/1` (base URL, timeouts, headers) and reuse it.
- Use the non-bang functions in application code and match on `{:ok, response}` / `{:error, reason}`; reserve bang functions for scripts and tests.
- Always set an explicit `receive_timeout`.
- Handle `404`, `429` and `5xx` in separate branches, not one generic non-2xx branch.
- Retry only idempotent requests. When Oban owns retries (as in delivery), set `retry: false` on the client so attempts are not multiplied.
- Stub every external call in tests with `Req.Test`; the test suite must never reach a real host.
- Keep real hosts and secrets out of code and commits.

## Ecto

- Enforce rules in the database too: `null: false`, foreign keys, unique indexes. Mirror them with `unique_constraint/3` in changesets.
- Migrations must be reversible. Never edit a migration that has been merged; add a new one.
- Use `Ecto.Multi` or `Repo.transact/1` when several writes must succeed together.
- Append-only tables (audit logs) get no update or delete functions in the context.
- Query with indexes in mind; add the index in the same change that adds the query.
- Use `cast/3` with an explicit allowlist of fields for external input and `change/2` only for trusted internal updates.
- Compose queries with named bindings and parameters; never interpolate input into SQL.
- Avoid N+1: preload or join what a list needs instead of fetching per row.
- Keep `Repo` calls in the persistence layer of the context; business rules stay in pure functions.

## Oban

- Declare queues and their concurrency in config before adding a worker that uses them.
- Enqueue jobs (`Oban.insert/1`) from a context function, never from a controller or LiveView.
- Job args are JSON-serializable maps with string keys; store ids, not structs.
- `perform/1` must be **idempotent**: running it twice must not double the effect.
- Set `max_attempts`, and a custom `backoff/1` when the retry policy matters. Return `{:ok, _}`, `{:error, _}` to retry, or `{:cancel, reason}` to stop for good.
- Use `unique` options to avoid enqueueing the same logical job twice, and do not rely on them alone for correctness.
- In tests use `testing: :manual` and `Oban.Testing` (`assert_enqueued`, `perform_job`), and cover every return path of the worker.

## OTP

- Supervise every long-lived process; choose a restart strategy on purpose and say why in a comment when it is not obvious.
- Do not use a GenServer for something a plain function or a database row can do.
- Emit `:telemetry` events for important operations (delivery attempted, succeeded, failed) and attach handlers in one place.

## Tests

- Name tests after the spec: `describe "Requirement: <name>"` and `test "Scenario: <name>"`, so scenario coverage can be checked by name.
- Never modify or delete existing tests unless the proposal says so; add new test files instead.
- Run `mix precommit` (compile with warnings as errors, format, test) before finishing.
