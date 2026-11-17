# Design

## Context

See proposal.md for the motivation. What exists:

- **API.** `GET /api/v1/events` (filters `merchant_id`, `type`; `CourierWeb.Params.pagination/1`: `limit` 1..100, default 50, `cursor`), `GET /api/v1/events/:id` (with deliveries), `GET /api/v1/deliveries/:id` (attempts and resends preloaded by `Courier.Delivery.get_delivery/1`), `POST /api/v1/deliveries/:id/resend` (`write`), `GET /api/v1/me` (key name and scopes), `GET /api/v1/merchants` and `GET /api/v1/endpoints` (both paginated, endpoints filterable by `merchant_id`). Errors use `{"error": {"code", "message"}}`, rendered by `CourierWeb.FallbackController`.
- **Context.** `Courier.Delivery.list_deliveries/1` (filters `status`, `endpoint_id`, `event_id`; keyset pagination with `Courier.Pagination`, newest first), used by the MCP tools. A delivery has no `merchant_id`: it belongs to an event (`merchant_id`, `type`, `received_at`) and an endpoint. `deliveries` has indexes on `(endpoint_id, status)` and `resend_of_id`, none on `(inserted_at, id)`; `events` has `(inserted_at, id)`, `(merchant_id, inserted_at)` and `(type)`.
- **SPA** (step 9). TanStack Router with file routes in `frontend/src/routes/`, `createAppRouter(queryClient, history?)` in `src/router.tsx` with `{ queryClient }` as router context, TanStack Query, shadcn components already in `src/components/ui/` (alert, badge, button, card, dialog, dropdown-menu, field, input, label, select, separator, skeleton, sonner, table, tooltip), React Hook Form, Zod and MSW installed. Tests in `frontend/tests/`, with `tests/setup.ts` (jest-dom, cleanup, `scrollTo` and `matchMedia` stubs) and `tests/render.tsx` (`renderApp(path)`: the whole app with memory history and a fresh cache).
- **Gate.** Every existing file under `test/` and `frontend/tests/` is protected, including `tests/setup.ts`, `tests/render.tsx` and `tests/app.test.tsx`; at most about 600 changed lines and 20 files per task.

## Goals / Non-Goals

**Goals:** every list, filter and detail served by the existing API style (one request per page, no N+1 from the SPA); shareable URLs for filtered lists; a SPA whose network boundary is mocked with MSW in tests; tasks that each fit the gate.

**Non-Goals:** live refresh (step 12), merchants and endpoints pages (step 11), counts or totals in lists, sorting other than newest first, an OpenAPI document (the TypeScript types are written by hand from the JSON views), and accessibility audits beyond semantic HTML, labels and text statuses.

## Decisions

### Backend

**Delivery filters in the context.** `list_deliveries/1` gains `:merchant_id`, `:event_type`, `:since` and `:until` (`DateTime`s). It always joins the event (`join: e in assoc(d, :event)`) and preloads it from the join (`preload: [event: e]`), so every listed delivery carries `event.type` and `event.merchant_id` in the same query; the filters are `where`s on `e.merchant_id`, `e.type`, and `d.inserted_at >= since` / `d.inserted_at < until`. `Courier.Pagination` orders by the first binding's `inserted_at` and `id`, so the join does not change the order. The MCP tools keep passing the options they pass today; preloading the event is invisible to them. `get_delivery/1` also preloads the event.
*Alternative:* denormalizing `merchant_id` and `event_type` onto deliveries — faster filters, but a migration with a backfill and two more columns to keep consistent; not needed at demo scale.

**Index.** A migration adds `create index(:deliveries, [:inserted_at, :id])`, the order of the new list. Filtered lists use it to walk newest first and filter rows on the way (and the existing `(endpoint_id, status)` index for endpoint filters). Measured numbers come in step 14.

**Event time range.** `list_events/1` gains `:since` and `:until` on `received_at` (the time shown to operators). `received_at` and `inserted_at` are set in the same insert, so ordering by `inserted_at` and filtering by `received_at` agree.

**Parsing and errors.** `CourierWeb.Params.time_range/1` reads `since` and `until` with `DateTime.from_iso8601/1` (an offset is required; a value without one is invalid) and returns `{:ok, %{since: dt | nil, until: dt | nil}}` or `{:error, {:invalid_param, name}}`. `DeliveryController.index` checks `status` against the four statuses the same way. `FallbackController` gains one clause for `{:error, {:invalid_param, name}}`: `422`, code `invalid`, message ``"`<name>` is invalid."``. Pagination errors keep their current clause.

**Views.** `DeliveryJSON.index/1` renders `{"data": [...], "next_cursor": ...}`, each item with the fields in the spec (`event_type` and `merchant_id` from the preloaded event, `inserted_at`). `show/1` adds `inserted_at`, `event_type` and `merchant_id`; nothing is removed.

### Frontend

**Structure** (feature folders, as the frontend skill sets):

```text
src/lib/api/client.ts        apiFetch: base path /api/v1, Bearer header, JSON, ApiError
src/lib/api/types.ts         hand-written types of the JSON views used here
src/lib/api/query-keys.ts    every query key in one place
src/lib/session.ts           read, write and clear the key in sessionStorage
src/lib/format.ts            dates in the user's locale; datetime-local <-> UTC ISO
src/features/auth/           sign-in form, useMe, sign-out, unauthorized handling
src/features/events/         events table, filters, event detail
src/features/deliveries/     deliveries table, filters, status badge, timeline, resend
src/routes/                  sign-in.tsx, _app.tsx (guard + layout), _app/events.*, _app/deliveries.*, _app/failed.tsx
```

**API client.** `apiFetch<T>(path, { method, query, signal })` builds the URL from defined query values only, adds `Authorization: Bearer <key>` from session storage, and parses JSON. A non-2xx answer throws `ApiError { status, code, message }` from the error shape (or a generic message when the body is not that shape); a network failure throws `ApiError` with `status: 0`. A `401` also calls the handler registered with `onUnauthorized(fn)`, which `main.tsx` sets to: clear the key, `queryClient.clear()`, navigate to `/sign-in?reason=expired&redirect=<current path>`. Tests register the same handler through the router they render.

**Key storage.** `sessionStorage` under `courier.apiKey`, as the API keys ADR decides; nothing else stores it. The sign-in form calls `GET /api/v1/me` with the candidate key passed explicitly (not yet stored); only a `200` stores it. `401` → "This key was not accepted."; `status: 0` or `5xx` → "Courier could not be reached."

**Guard.** A pathless layout route `_app` wraps every data page. Its `beforeLoad` redirects to `/sign-in?redirect=<href>` when no key is stored, then `ensureQueryData` loads `/me` (cached, `staleTime: Infinity` until sign-out), so the layout can show the key name and scopes and pages can read `scopes`. The overview (`/`) and `/sign-in` stay outside `_app`, so the bootstrap tests keep passing unchanged and the overview sends no request without a key; the overview shows a "Sign in" link when no key is stored. Navigation links: Overview, Events, Deliveries, Failed.

**Lists.** Filters live in the URL search params, validated with Zod in each route's `validateSearch` (unknown or invalid values are dropped, not errors). Each list is a `useInfiniteQuery` keyed by `[resource, 'list', filters]`, with `getNextPageParam: page => page.next_cursor ?? undefined` and a "Load more" button while `hasNextPage`. Filter forms (React Hook Form + Zod, shadcn `Field`, `Select`, `Input`) apply on submit and navigate with the new search; a "Clear" action resets them. Time inputs are `datetime-local` in the operator's time zone, converted to UTC ISO for the URL and the API.
*Alternative:* numbered pages — the API has cursors only, and "Load more" maps onto them directly.

**Names instead of ids.** Merchant names (events list, filters) and endpoint URLs (deliveries list, filters, delivery page) come from one `GET /merchants?limit=100` and one `GET /endpoints?limit=100` query each, cached and shared across pages; an id not found there is shown as a shortened id. This avoids a request per row and backend changes, at the cost of the 100 limit (see Risks).

**Failed view.** `/failed` renders the deliveries list component with `status: 'failed'` fixed and the status filter hidden; its query key includes the status, so it shares cache entries with an identical deliveries filter.

**Delivery page.** `/deliveries/$deliveryId` loads `GET /deliveries/:id` (and the endpoints query for the URL). The timeline is an ordered list (`<ol>`), one entry per attempt: number, start time, duration in ms, status code (or the error), and the response body in a `<pre>` cut at 500 characters with "Show more". Statuses use one `StatusBadge` (icon + text) everywhere. Text from the API (payloads, bodies, errors) is rendered as React text only; nothing uses `dangerouslySetInnerHTML`.

**Resend.** A `ResendButton` on the delivery page: hidden unless the status is `succeeded` or `failed`; disabled with a tooltip and visible text when `/me` scopes lack `write`. It opens a shadcn `Dialog` naming the endpoint URL; "Resend" runs a `useMutation` of `POST /deliveries/:id/resend`. On success it invalidates `['deliveries']` and `['events']`, shows a Sonner toast "Resend created", and navigates to the new delivery. On `ApiError` it shows the API message in the dialog (an `Alert`) and stays.

**Tests.** New helpers in new files (the existing ones are protected): `tests/support/server.ts` (an MSW `setupServer` plus `useApiServer()` that registers `beforeAll`/`afterEach`/`afterAll` in the calling test file, with `onUnhandledRequest: 'error'`), `tests/support/fixtures.ts` (factories for events, deliveries, attempts, merchants, endpoints and `/me`), and `tests/support/session.ts` (`signIn(scopes)` stores a key before `renderApp`). Each spec requirement gets a `describe("Requirement: …")` and each scenario an `it("Scenario: …")`, in one test file per task.

## Risks / Trade-offs

- [More than 100 merchants or endpoints] → names fall back to shortened ids; the filters list only the first 100. Acceptable for the demo; step 11 adds the endpoints pages, which can page through them.
- [Joined filters get slow on large tables] → the `(inserted_at, id)` index keeps the default list cheap; denormalizing is the documented alternative if step 14's measurements show a problem.
- [A key in session storage can be read by any script on the page] → accepted by the API keys ADR for a local demo; the SPA renders API text as text only, and loads no third-party scripts.
- [Lists go stale until navigation] → "Load more" and filters refetch; a manual refresh button is not added because step 12 pushes changes.

## Migration Plan

One additive migration (an index). The new and extended endpoints are additive; existing clients keep working. Rollback: revert the change and roll back the migration.
