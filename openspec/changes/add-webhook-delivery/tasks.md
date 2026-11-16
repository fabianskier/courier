# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines, tests included). Put new tests and helpers in new files: existing files under `test/` are protected.

## 1. Building blocks

- [ ] 1.1 Add `{:req, "~> 0.7"}` to `mix.exs` and implement `Courier.Delivery.Signer` as in design.md; verify with new tests in `test/courier/delivery/signer_test.exs` (`describe "Requirement: Signed webhook requests"`): "Scenario: Standard Webhooks test vector" and a rotation case where the header holds two signatures, each verifiable with its own secret
- [ ] 1.2 Generate the `create_attempts` migration with the `attempts_append_only()` trigger and implement `Courier.Audit.Attempt` (insert changeset only) and `Courier.Audit.list_attempts/1` as in design.md, plus an attempt fixture in a new file under `test/support/fixtures/`; verify with new tests in `test/courier/audit/attempt_test.exs`: "Scenario: Update rejected", "Scenario: Delete rejected outside retention", "Scenario: Delete allowed for retention", the unique `(delivery_id, number)` index, and `list_attempts/1` ordering
- [ ] 1.3 Implement `Courier.Delivery.RetryPolicy` (`classify/2`, `delay/3`, `parse_retry_after/2`, `next/3`) as in design.md; verify with new tests in `test/courier/delivery/retry_policy_test.exs`: classification of `200`, `204`, `302`, `400`, `404` (with and without `retry_on_4xx`), `408`, `429`, `500`, `503` and `{:error, _}`, "Scenario: Delay grows and is capped" with an injected random function, `Retry-After` as seconds, as HTTP date, invalid, and capped, and `next/3` before and at the window end
- [ ] 1.4 Implement `Courier.Delivery.Client` and start `Courier.Finch` in `Courier.Application` as in design.md, with `config/test.exs` setting `plug: {Req.Test, Courier.Delivery.Client}`; verify with new tests in `test/courier/delivery/client_test.exs` using `Req.Test` stubs: a `200`, "Scenario: Redirect not followed" at the client level (the stub for the location is never called), a transport timeout returned as `{:error, "timeout"}`, a 10 KB body truncated to 4096 bytes, invalid UTF-8 and NUL bytes sanitized, and `Retry-After` returned

## 2. Delivering

- [ ] 2.1 Implement `Courier.Delivery.record_attempt/3` and `fail_without_attempt/2` in a new `lib/courier/delivery.ex` as in design.md; verify with new tests in `test/courier/delivery/record_attempt_test.exs`: attempt numbering 1, 2, 3 with `attempt_count` updated, `succeeded`/`failed` setting `completed_at` and clearing `next_attempt_at`, `retry_at` setting `next_attempt_at`, and "Scenario: Late result ignored"
- [ ] 2.2 Implement `Courier.Delivery.Worker` as in design.md (request body, headers, signature redaction in stored headers, URL check, classification, snooze); verify with new tests in `test/courier/delivery/worker_test.exs` using `Oban.Testing.perform_job/3` and `Req.Test` stubs, named after the spec scenarios that end in one attempt: "Request headers and body" (the stub verifies the signature with the endpoint secret), "Two signatures during rotation", "Endpoint answers 200", "Client error", "Redirect not followed", "Window already ended", "Host now resolves to a private address" (through `Courier.Endpoints.TestResolver`) and "Attempt recorded"
- [ ] 2.3 Cover the retry paths of `Courier.Delivery.Worker`, fixing the worker only if a test shows a gap; verify with new tests in `test/courier/delivery/worker_retry_test.exs`: "Scenario: Server error", "Scenario: Timeout", "Scenario: 4xx retried when configured", "Scenario: Retry-After honoured", "Scenario: Retry-After capped" and "Scenario: Window ends after a failure", checking the snooze value, `next_attempt_at` and the stored attempts

## 3. Queues and ingestion

- [ ] 3.1 Implement `Courier.Delivery.Queues`, `Courier.Delivery.ObanQueueControl` and `Courier.Delivery.QueueManager` (started after Oban in `Courier.Application`, queue control module from config, a stub in `config/test.exs` that does nothing unless a test registers itself), and call `QueueManager.sync/1` from `Endpoints.create_endpoint/1` and `update_endpoint/2` as in design.md; verify with new tests in `test/courier/delivery/queue_manager_test.exs`: "Scenario: Queues started at boot" (a manager started with `start_supervised!/1`) and "Scenario: Queue follows endpoint changes"
- [ ] 3.2 In `Courier.Ingestion`: insert the delivery jobs in the ingestion `Ecto.Multi`, answer a repeat for a disabled merchant as a repeat, and order deliveries by endpoint creation in every response, as in design.md; verify with new tests in `test/courier/ingestion_delivery_test.exs`: "Scenario: Jobs stored with the event", "Scenario: Job in the endpoint's queue", "Scenario: Failure while storing jobs" (a failing step appended to `ingest_multi`), "Scenario: Repeat after the merchant was disabled" (and a reused key in the same situation), and "Scenario: Stable delivery order"; check that every existing test still passes unchanged

## 4. API and docs

- [ ] 4.1 Implement `DeliveryController.show`, `DeliveryJSON` and the `GET /api/v1/deliveries/:id` route with the `read` scope, backed by a `Courier.Delivery.get_delivery/1` that preloads attempts, as in design.md; verify with new tests in `test/courier_web/controllers/delivery_read_test.exs`: "Scenario: Delivery with attempts" (no `request_headers` and no signature in the body), "Scenario: Unknown delivery" and a wrong-scope `403`
- [ ] 4.2 Document delivery in `docs/architecture.md` (new section "Webhook delivery": request body and headers, how a receiver verifies the signature, retry rules and timing, attempts and the trigger, queues per endpoint, the read API with a `curl` example, and the DNS rebinding note in "Security notes"), and mark step 4a done in `docs/roadmap.md` with `add-endpoint-health` (FR-17, FR-36) as the next step; verify `mix precommit`, `sh .smelt/checks.sh` and `openspec validate add-webhook-delivery --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-webhook-delivery <task>` and review before merging.
- Archive the change after the last merge and check it end to end against a local receiver (signature verified, a `503` retried, a `400` failed).
- Then propose `add-endpoint-health` (degraded flag, consecutive failures, slow-endpoint isolation test).
