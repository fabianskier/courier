# Tasks

Each task must stay within the gate's diff budget (about 600 changed lines and 20 files, tests included). Existing files under `test/` and `frontend/tests/` are protected: put new tests and helpers in new files. Read design.md before each task. Frontend tests are named after the spec (`describe("Requirement: …")`, `it("Scenario: …")`) and mock the network with MSW.

## 1. API

- [ ] 1.1 Add the migration with `index(:deliveries, [:inserted_at, :id])` (via `mix ecto.gen.migration`); extend `Courier.Delivery.list_deliveries/1` with `:merchant_id`, `:event_type`, `:since` and `:until`, joining and preloading the event as in design.md, and preload the event in `get_delivery/1`; extend `Courier.Ingestion.list_events/1` with `:since` and `:until` on `received_at`; verify with new tests in `test/courier/delivery_list_filters_test.exs` (each new filter alone and combined, the time bounds inclusive/exclusive, malformed ids match nothing, the event preloaded, existing MCP options unchanged) and `test/courier/event_time_filter_test.exs`
- [ ] 1.2 Add `CourierWeb.Params.time_range/1`, the `{:error, {:invalid_param, name}}` clause in `FallbackController`, `GET /api/v1/deliveries` (`DeliveryController.index`, `read` scope, status check, `DeliveryJSON.index/1`), the new fields in `DeliveryJSON.show/1`, and `since`/`until` in `EventController.index`; verify with new tests in `test/courier_web/controllers/delivery_list_test.exs` (every scenario of "List deliveries" and "Filter deliveries"), `test/courier_web/controllers/event_time_range_test.exs` ("Scenario: Events in a time range", "Scenario: Invalid time range rejected") and `test/courier_web/controllers/delivery_read_fields_test.exs` ("Scenario: Delivery shows its event and creation time")

## 2. Sign-in

- [ ] 2.1 Add `src/lib/api/` (client, types, query keys), `src/lib/session.ts`, `src/features/auth/`, the `/sign-in` route, the `_app` layout route (guard, navigation, key name and scopes, sign-out), the `401` handling in `main.tsx`, and the "Sign in" link on the overview; add `tests/support/server.ts`, `tests/support/fixtures.ts` and `tests/support/session.ts` as in design.md; verify with `frontend/tests/dashboard-access.test.tsx` covering every scenario of `specs/dashboard-access/spec.md`, and check that the bootstrap tests in `frontend/tests/app.test.tsx` still pass unchanged

## 3. Lists

- [ ] 3.1 Add `src/lib/format.ts`, the merchants and endpoints lookup queries, the events list (`_app/events` route with Zod search, filters, "Load more", loading, empty and error states) and the event page (`_app/events/$eventId`); verify with `frontend/tests/events.test.tsx` covering every scenario of "Events list" and "Event page"
- [ ] 3.2 Add `StatusBadge`, the deliveries list (`_app/deliveries` route with Zod search, filters, "Load more", states) and the failed view (`_app/failed`); verify with `frontend/tests/deliveries-list.test.tsx` covering every scenario of "Deliveries list" and "Failed deliveries view"

## 4. Delivery page and resend

- [ ] 4.1 Add the delivery page (`_app/deliveries/$deliveryId`): summary, pending and skipped states, the attempt timeline with "Show more", and the resend links; verify with `frontend/tests/delivery-page.test.tsx` covering every scenario of "Delivery page", "Attempt timeline" and "Resend links"
- [ ] 4.2 Add `ResendButton` with its confirmation dialog, scope and status rules, success navigation with a toast, and the API error message; verify with `frontend/tests/resend.test.tsx` covering every scenario of "Resend with confirmation" and "Resend only when allowed"

## 5. Docs

- [ ] 5.1 Update `docs/architecture.md` ("Dashboard SPA": routes, sign-in, API client, lists, resend; the new `GET /api/v1/deliveries` in "API surface" and the time range of `GET /api/v1/events`), add a dashboard step to the README walkthroughs (open <http://localhost:4000>, sign in with the `demo` key, open "Failed", resend), and mark step 10 done in `docs/roadmap.md` with step 11 next; verify `sh .smelt/checks.sh` and `openspec validate add-dashboard-deliveries --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-dashboard-deliveries <task>` and review before merging.
- After the last merge, run the Docker demo, sign in with the `demo` key printed by `bin/seed`, browse the failed deliveries of `harbor-fail`, resend one, then archive the change.
