# Proposal

## Why

The dashboard shows data as of the last request: a delivery that fails, a new event or an endpoint that turns degraded only appears after a reload or a filter change. FR-28 asks for a refresh within 5 s of a change without a manual reload, and the Channels ADR decides how: small change notices pushed over a Phoenix Channel, after which the SPA refetches over REST.

## What Changes

- **Change notices**: after commit, every change the dashboard shows is broadcast over Phoenix PubSub as a small notice with ids and a status only (never payloads, bodies or secrets): `event_ingested`, `delivery_changed` (created, retry scheduled, succeeded, failed, resent), `endpoint_changed` (created, updated, secret rotated, degraded, recovered) and `merchant_changed`.
- **Dashboard socket**: `/socket` (WebSocket only) authenticated with the same API key (`read` scope), sent through the client's auth token header so it never appears in a URL or a log; a `DashboardChannel` with topics `dashboard:events`, `dashboard:deliveries`, `dashboard:endpoints` and `dashboard:merchants` forwards the notices. An open socket re-checks its key every 30 seconds and closes once the key is revoked.
- **SPA live updates**: while signed in, the SPA joins the four topics and invalidates the affected TanStack Query keys, coalescing bursts so it refetches at most about once a second per resource; after a reconnect it refetches every active query. The layout shows whether updates are live or reconnecting.
- **Dependency**: the `phoenix` JavaScript client (same version as the server, 1.8.16) and `@types/phoenix`, installed before the tasks.
- **Not in this change**: notices for API key changes other than revocation, per-merchant topics or authorization finer than the `read` scope, and pushing data in notices.

## Capabilities

### New Capabilities
- `dashboard-live-updates`: change notices, the authenticated dashboard socket and its topics, and how the SPA refreshes from them.

### Modified Capabilities
None. Existing API responses and behaviours do not change.

## Impact

- Backend: a new `Courier.Notices` module called after commit where `Courier.Telemetry` already emits (ingestion, attempt outcomes, the window sweeper, resend, endpoint health) and in `Courier.Endpoints` and `Courier.Merchants` after a successful change; `CourierWeb.DashboardSocket` and `CourierWeb.DashboardChannel` (with a periodic key check); a `socket` line in `CourierWeb.Endpoint`; `test/support/channel_case.ex`.
- Frontend: `src/lib/live/` (socket, topic joins, notice-to-query mapping, coalescing), a hook started by the `_app` layout and stopped on sign-out, and a status indicator.
- No database changes. Existing tests are not modified.
