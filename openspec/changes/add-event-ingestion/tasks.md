# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected.

## 1. Test support

- [x] 1.1 Add `CourierWeb.LogCapture.capture_debug_log/1` in a new file `test/support/log_capture.ex` as in design.md, and a new test file `test/courier_web/plugs/token_logging_test.exs` (`async: false`, `describe "Requirement: Tokens never leak"`, `test "Scenario: Rejected token not echoed"`) that sends a request with an unknown token through `GET /api/v1/me`, asserts the captured debug log is not empty and does not contain the token, and that the response body does not contain it; verify `sh .smelt/checks.sh` passes

## 2. Data and ingestion

- [x] 2.1 Generate the `create_events` and `create_deliveries` migrations and implement `Courier.Ingestion.Event`, `Courier.Delivery.Delivery`, `EventFilter.valid_type?/1` and the `order: :desc` option of `Courier.Pagination` as in design.md, plus `test/support/fixtures/events_fixtures.ex`; verify with new tests in `test/courier/endpoints/event_type_test.exs` (valid and invalid types), `test/courier/pagination_desc_test.exs` (newest-first pages with no repeats) and a schema test that a second non-resend delivery for the same event and endpoint violates the unique index
- [x] 2.2 Implement `Courier.Ingestion.ingest/2` and the public `ingest_multi` as in design.md; verify with new tests in `test/courier/ingestion_test.exs` named after the spec scenarios at the context level: "Occurrence time defaults to receipt", "Exact repeat", "Same payload with keys in another order", "Key reused with a different body", "Simultaneous repeats", "Event for unknown merchant", "Invalid type or payload", "Merchant disabled", "Payload too large", "Matching and filtered endpoints", "Retry window recorded", "Merchant without endpoints", "Failure while storing deliveries" and "Missing key" / "Malformed key" (key validation)

## 3. API

- [ ] 3.1 Implement `EventController.create`, `EventJSON`, the fallback clauses for `:merchant_disabled`, `:idempotency_key_reused` and `:payload_too_large`, the `POST /api/v1/events` route with the `ingest` scope, and `length: 1_048_576` in `Plug.Parsers` as in design.md; verify with new tests in `test/courier_web/controllers/event_ingestion_test.exs` named "Scenario: Event accepted", "Scenario: Wrong scope", "Scenario: Missing key", "Scenario: Malformed key", "Scenario: Exact repeat", "Scenario: Key reused with a different body", "Scenario: Merchant disabled" and "Scenario: Payload too large" over HTTP, checking status codes, error codes and that rejected requests store nothing
- [ ] 3.2 Implement `EventController.index` and `show` with the `read` scope as in design.md; verify with new tests in `test/courier_web/controllers/event_read_test.exs` named "Scenario: List and filter events", "Scenario: Show an event with its deliveries" and "Scenario: Unknown event", plus newest-first pagination over HTTP
- [ ] 3.3 Document ingestion (headers, body, status and error codes, idempotency rules including that repeats must send the same `occurred_at`, fan-out and delivery statuses, the read API, with `curl` examples) in `docs/architecture.md` and mark step 3 done in `docs/roadmap.md` (removing the note about the vacuous token test, now fixed by task 1.1); verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-event-ingestion --strict` pass and every scenario in `specs/event-ingestion/spec.md` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-event-ingestion <task>` and review before merging.
- Archive the change after the last merge and check it end to end with `curl`.
- Then propose `add-webhook-delivery` (roadmap step 4).
