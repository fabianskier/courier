# Tasks

Each task must stay within the gate's diff budget (about 800 changed lines and 20 files, tests included; the route tree and the npm lockfile are not counted). Existing test files are protected: put new tests and helpers in new files. Read design.md before each task. Tests are named after the spec (`describe "Requirement: …"` / `test "Scenario: …"` in Elixir, `describe`/`it` in the frontend).

## 1. Backend

- [x] 1.1 Add `Courier.Notices` and call it after commit in ingestion, attempt outcomes, the window sweeper, resend, endpoint health transitions, and the endpoint and merchant create/update/rotate functions, as in design.md; verify with new tests in `test/courier/notices_test.exs` covering every scenario of "Change notices" and "Notices carry ids only"
- [ ] 1.2 Add `CourierWeb.DashboardSocket` (auth token, `read` scope), `CourierWeb.DashboardChannel` (four topics, PubSub forwarding, the periodic key check) and the `/socket` line in `CourierWeb.Endpoint`, plus `test/support/channel_case.ex`; verify with new tests in `test/courier_web/channels/dashboard_socket_test.exs` and `dashboard_channel_test.exs` covering every scenario of "Authenticated dashboard socket" and "Dashboard topics"

## 2. Frontend

- [ ] 2.1 Add `src/lib/live/` (transport over `phoenix`'s `Socket` with `authToken`, notice-to-query mapping, the coalescer), `useLiveUpdates` in the `_app` layout, disconnect on sign-out and on `401`, the reconnect refetch, and the `LiveStatus` indicator; verify with `frontend/tests/live-updates.test.tsx` covering every scenario of "Dashboard refreshes from notices" and "Reconnect and live status"

## 3. Docs

- [ ] 3.1 Add a "Live updates" section to `docs/architecture.md` (notices, socket auth with the auth token header, topics, key re-check, client coalescing and reconnect), add a README demo step (keep the failed view open while `bin/simulate` runs and watch it fill without reloading), and mark step 12 done in `docs/roadmap.md` with step 13 next; verify `sh .smelt/checks.sh` and `openspec validate add-dashboard-live-updates --strict` pass and every scenario in `specs/` has a test with the same name

## Workflow follow-up

- Build each task with `mix smelt.task ~/code/courier add-dashboard-live-updates <task> --model opus` (3.1 with `--model sonnet`); review and merge each task before starting the next.
- After the last merge, run the Docker demo with the dashboard open, run `bin/simulate`, and check that the lists update within 5 seconds; then archive the change.
