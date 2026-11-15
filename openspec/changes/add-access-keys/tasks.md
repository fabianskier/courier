# Tasks

## 1. Keys and the access context

- [ ] 1.1 Generate the `create_api_keys` migration (`mix ecto.gen.migration create_api_keys`) and implement `Courier.Access.ApiKey` and `Courier.Access` (`create_key/1`, `list_keys/0`, `revoke_key/1`, `authenticate/1`, `has_scope?/2`) as in design.md, plus a test helper in a new file `test/support/fixtures/access_fixtures.ex` (`api_key_fixture/1` returning the key and its token; existing files under `test/` are protected, so do not edit `conn_case.ex` or `data_case.ex`); verify with new tests in `test/courier/access_test.exs` named after the spec for "Key created with scopes", "Token is not stored in plaintext", "Duplicate name rejected", "Invalid scopes rejected", "Token format", "Tokens differ", "Listing shows keys without secrets", "Revoked key no longer authenticates" (at context level: `authenticate/1` returns `{:error, :unauthorized}`) and "Unknown key", plus `has_scope?/2` and that `inspect/1` of a key does not show the hash

## 2. Command line

- [ ] 2.1 Implement `mix courier.keys.create`, `mix courier.keys.list` and `mix courier.keys.revoke` as in design.md, with `@shortdoc` and `@moduledoc` usage; verify with new tests in `test/mix/tasks/courier_keys_test.exs` for "Create from the command line", "Invalid input from the command line" and "List and revoke from the command line"

## 3. Authenticated API

- [ ] 3.1 Implement `CourierWeb.APIErrorJSON`, `CourierWeb.FallbackController`, the `Authenticate` and `RequireScope` plugs, the `/api/v1` scope with an `:authenticated` pipeline, and `GET /api/v1/me` (`MeController`); verify with new tests in `test/courier_web/` named after the spec for "Valid token", "Missing token", "Unknown token", "Malformed header", "Revoked key no longer authenticates" (over HTTP), "Who am I", "Error body", "Rejected token not echoed", and, for scopes, "Key with the required scope" and "Key without the required scope" using a test-only route or by calling `RequireScope` directly on a conn
- [ ] 3.2 Document API authentication (header, scopes, error shape, the Mix tasks and `GET /api/v1/me` with a `curl` example) in a new "Authentication" section of `docs/architecture.md`, and mark step 1 done in `docs/roadmap.md`; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-access-keys --strict` pass and every scenario in `specs/api-access/spec.md` has a test with the same name

## Workflow follow-up

- Review and merge each task through `mix smelt.task ~/code/courier add-access-keys <task>`.
- Archive the change after the last merge (`openspec archive add-access-keys`).
- Then propose `add-merchants-endpoints` (roadmap step 2).
