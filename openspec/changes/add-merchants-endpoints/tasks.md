# Tasks

Each task must stay within Smelt's diff budget (about 400 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected.

## 1. Encryption

- [x] 1.1 Add `{:cloak_ecto, "~> 1.3"}`, `Courier.Vault` (AES.GCM, tag `"AES.GCM.V1"`), `Courier.Encrypted.Binary`, the vault as a child of `Courier.Application`, fixed non-secret keys in `config/dev.exs` and `config/test.exs`, and a required `COURIER_ENCRYPTION_KEY` (base64 of 32 bytes, clear error when missing or the wrong size) in the prod block of `config/runtime.exs`, as in design.md; verify with a new test `test/courier/vault_test.exs` that a value encrypts to different ciphertext and decrypts back, and that `sh .smelt/checks.sh` passes

## 2. Merchants

- [x] 2.1 Generate the `create_merchants` migration and implement `Courier.Merchants.Merchant`, `Courier.Merchants` (`create_merchant/1`, `get_merchant/1` returning `{:error, :not_found}` for unknown or malformed ids, `list_merchants/1` paginated, `update_merchant/2`) and `Courier.Pagination` as in design.md, plus `test/support/fixtures/merchants_fixtures.ex`; verify with new tests in `test/courier/merchants_test.exs` (creation, invalid name, update and disable, not found) and `test/courier/pagination_test.exs` (pages of 2, 2 and 1 with no repeats, invalid cursor)
- [x] 2.2 Implement `CourierWeb.Params.pagination/1`, the fallback clauses for `:invalid_cursor` and `:invalid_pagination`, `MerchantController`, `MerchantJSON` and the merchant routes with `read`/`write` scopes as in design.md; verify with new tests in `test/courier_web/controllers/merchant_controller_test.exs` named after every scenario in `specs/merchants/spec.md`

## 3. URL policy and event filter

- [x] 3.1 Implement `Courier.Endpoints.URLPolicy` and `Courier.Endpoints.DNSResolver` as in design.md, the convention-based `Courier.Endpoints.TestResolver` in a new file `test/support/test_resolver.ex`, and the per-environment URL policy config; verify with new tests in `test/courier/endpoints/url_policy_test.exs` named "Scenario: Plain http rejected", "Scenario: Private address rejected" (every IPv4 and IPv6 range in design.md, IP literals and resolved names, IPv4-mapped IPv6), "Scenario: Credentials in URL rejected", "Scenario: Unresolvable host rejected" and "Scenario: Allowlisted host accepted", plus a public https URL that passes
- [ ] 3.2 Implement `Courier.Endpoints.EventFilter` (`valid_pattern?/1`, `matches?/2`) as in design.md; verify with new tests in `test/courier/endpoints/event_filter_test.exs` named "Scenario: Exact and wildcard matching", "Scenario: Empty list matches everything" and "Scenario: Invalid pattern rejected" (at the function level)

## 4. Endpoints

- [ ] 4.1 Generate the `create_endpoints` migration and implement `Courier.Endpoints.Endpoint` and `Courier.Endpoints` (`create_endpoint/1` returning the endpoint and its secret, `get_endpoint/1`, `list_endpoints/1` paginated with an optional `merchant_id`, `update_endpoint/2`), using the URL policy, the event filter and the delivery-setting ranges, plus `test/support/fixtures/endpoints_fixtures.ex`; verify with new tests in `test/courier/endpoints_test.exs` for "Scenario: Defaults applied", "Scenario: Setting out of range", "Scenario: Secret format", "Scenario: Secret encrypted at rest" (raw SQL on the row), "Scenario: Endpoint for unknown merchant" and "Scenario: Unsafe URL on update" at the context level, and that `inspect/1` of an endpoint shows no secret; also complete "Scenario: Disable a merchant" (its HTTP test from 2.2 could not check endpoints) with a new test in a new file `test/courier/merchant_endpoints_test.exs` that disables a merchant with an enabled and a disabled endpoint through `Courier.Merchants.update_merchant/2` and asserts both endpoints keep their own `enabled` flag
- [ ] 4.2 Implement `Courier.Endpoints.rotate_secret/2` and `signing_secrets/2` with the 24 h overlap as in design.md; verify with new tests in `test/courier/endpoints/rotation_test.exs` named "Scenario: Rotation with overlap" and "Scenario: Overlap ends" (passing `now`), plus a second rotation during the overlap replacing the previous secret

## 5. Endpoint API and wrap-up

- [ ] 5.1 Implement `EndpointController`, `EndpointJSON` and the endpoint routes (including `POST /api/v1/endpoints/:id/rotate_secret`) with `read`/`write` scopes as in design.md; verify with new tests in `test/courier_web/controllers/endpoint_controller_test.exs` named after the HTTP scenarios in `specs/webhook-endpoints/spec.md` ("Endpoint created", "Endpoint for unknown merchant", "List a merchant's endpoints", "Show without secret", "Disable an endpoint", "Unsafe URL on update", "Rotation with overlap", "Read-only key cannot rotate"), checking that no response except create and rotate contains a `secret`
- [ ] 5.2 Make `mix courier.keys.*` raise their process log level to at least `:info` as in design.md (check by hand in dev that `mix courier.keys.list` prints no SQL); document merchants, endpoints, the URL policy, secrets and rotation, pagination and `COURIER_ENCRYPTION_KEY` in `docs/architecture.md`; add to its "Security notes" that `cloak` 1.1.4 and `cloak_ecto` 1.3.0 have open advisories (CVE-2026-95105: unauthenticated AES-CTR cipher; CVE-2026-94206: PBKDF2 field ignores the iteration count) that do not affect courier because it uses only `Cloak.Ciphers.AES.GCM` and `Cloak.Ecto.Binary`, with the rule never to use Cloak's AES-CTR cipher or PBKDF2 fields and to upgrade both packages when fixed versions are released; and mark step 2 done in `docs/roadmap.md`; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-merchants-endpoints --strict` pass and every scenario in both specs has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-merchants-endpoints <task>` and review before merging.
- Archive the change after the last merge (`openspec archive add-merchants-endpoints`).
- Then propose `add-event-ingestion` (roadmap step 3).
