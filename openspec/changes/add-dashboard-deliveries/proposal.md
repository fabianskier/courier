# Proposal

## Why

The backend delivers, retries and records every attempt, but an operator can only see it through `curl`, LiveDashboard metrics or an MCP client. The dashboard's first pages answer the daily questions: what came in, what was delivered, what failed and why, and let the operator resend (FR-24 to FR-26). The SPA bootstrap (step 9) is in place, so this is the first change built on it.

## What Changes

- **Delivery listing API**: new `GET /api/v1/deliveries` (`read` scope), newest first with cursor pagination, filtered by `status`, `merchant_id`, `endpoint_id`, `event_id`, `event_type` and a time range (`since`, `until`). Each item carries the event type and merchant id so a list can be shown without one request per row.
- **Time range for events**: `GET /api/v1/events` accepts `since` and `until` (on the received time), next to `merchant_id` and `type`.
- **Delivery detail**: `GET /api/v1/deliveries/:id` also returns `inserted_at`, `event_type` and `merchant_id`. Additive; existing fields do not change.
- **Sign-in**: the dashboard asks for an API key once, checks it with `GET /api/v1/me`, keeps it in session storage (as the API keys ADR decides) and offers sign-out. A key that stops working sends the operator back to sign-in.
- **Events pages**: a filterable events list (merchant, type, time range, "load more") and an event page with its payload and deliveries.
- **Deliveries pages**: a filterable deliveries list (status, merchant, endpoint, event type, time range), a "Failed" view with failed deliveries only, and a delivery page with the attempt timeline (time, duration, status code, error, response body) and links between a delivery and its resends.
- **Resend**: a resend button on terminal deliveries with a confirmation dialog, available only to keys with the `write` scope; conflicts and disabled endpoints are explained, and a successful resend opens the new delivery.
- **Not in this change**: merchants and endpoints management (step 11), live updates (step 12; lists refresh on navigation and on demand), an OpenAPI document, and user accounts.

## Capabilities

### New Capabilities
- `dashboard-access`: signing in to the dashboard with an API key, keeping it for the browser session, signing out, and reacting to a rejected key or a missing scope.
- `dashboard-deliveries`: the dashboard's events and deliveries pages: lists with filters and pagination, event and delivery details, the attempt timeline, the failed view and the resend action.

### Modified Capabilities
- `event-ingestion`: "Read events" gains the time range filter.
- `webhook-delivery`: "Read a delivery with its attempts" gains `inserted_at`, `event_type` and `merchant_id`; a new requirement lists deliveries with filters.

## Impact

- Backend: `Courier.Delivery.list_deliveries/1` gains the merchant, event type and time filters; `Courier.Ingestion.list_events/1` gains the time filter; `DeliveryController.index`, `DeliveryJSON`, a time range parser in `CourierWeb.Params`, and one new route. One migration adds an index on `deliveries (inserted_at, id)`, the order of the new list; there is none today.
- Frontend: an API client and its types, sign-in, and the events and deliveries routes under `frontend/src/`; tests in `frontend/tests/` with MSW. No new npm dependencies (step 9 installed them).
- The MCP tools keep their behaviour: they pass the same options as before to `list_deliveries/1`.
- Existing tests are not modified.
