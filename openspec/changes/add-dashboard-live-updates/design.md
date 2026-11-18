# Design

## Context

See proposal.md for the motivation and the Channels ADR in `docs/decisions.md` for the approach. What exists:

- **After-commit hooks.** `Courier.Telemetry` emits after commit and once per change: `emit_event_ingested(event, deliveries)` in `Courier.Ingestion`; `emit_delivery_succeeded/failed/retry_scheduled` in `Courier.Delivery.record_attempt/3` and the window sweeper; the endpoint `degraded`/`recovered` events in `Courier.Delivery`. `Courier.Delivery.resend/2`, `Courier.Endpoints.create_endpoint/1`, `update_endpoint/2`, `rotate_secret/2` and `Courier.Merchants.create_merchant/1`, `update_merchant/2` return `{:ok, ...}` after their transaction.
- **PubSub and endpoint.** `Courier.PubSub` is started; `CourierWeb.Endpoint` has only the LiveDashboard socket (`/live`). Phoenix 1.8.16 supports `websocket: [auth_token: true]`: the JS client's `authToken` travels in the `Sec-WebSocket-Protocol` header and reaches `connect/3` as `connect_info.auth_token`.
- **Access.** `Courier.Access.authenticate/1` returns the key for a valid token; `has_scope?/2`; keys are revoked by `mix courier.keys.revoke`, which runs in its own OS process.
- **SPA.** `_app` layout (signed-in pages), `signOut/2` and the `401` handler in `src/features/auth/session.ts`, query keys in `src/lib/api/query-keys.ts` (`me`, `events.*`, `deliveries.*`, `merchants`, `merchantList`, `merchant(id)`, `endpoints`, `endpointList`, `endpoint(id)` and friends), `phoenix` 1.8.16 and `@types/phoenix` installed.

## Goals / Non-Goals

**Goals:** domain code that announces changes without knowing about sockets; notices that are safe to send to any `read` key; a client that refetches promptly but never floods the API; everything testable without a real browser socket.

**Non-Goals:** delivering notices across nodes (one node, as in the deployment ADR), replaying missed notices (a reconnect refetches instead), and per-merchant authorization.

## Decisions

**`Courier.Notices` in the domain.** One module with `event_ingested/1`, `delivery_changed/1`, `endpoint_changed/1` and `merchant_changed/1`, each building the payload from a struct (ids, status or type only) and calling `Phoenix.PubSub.broadcast(Courier.PubSub, "notices:<resource>", {:notice, name, payload})`. It is called right next to each `Courier.Telemetry` emit (already after commit), and in `Delivery.resend/2`, `Endpoints` and `Merchants` after a successful transaction. Payload maps use string keys so they serialize as they are tested.
*Alternative:* a telemetry handler that turns telemetry events into notices — fewer call sites, but endpoint and merchant edits have no telemetry events, and notices would depend on telemetry metadata staying complete.

**Socket and channel.** `socket "/socket", CourierWeb.DashboardSocket, websocket: [auth_token: true], longpoll: false`. `connect(_params, socket, %{auth_token: token})` authenticates and requires `read`; anything else returns `:error`. `id/1` returns nil (no server-initiated disconnect by id is needed). `CourierWeb.DashboardChannel` handles `"dashboard:" <> resource` for the four resources: `join` subscribes to `"notices:<resource>"` and `handle_info({:notice, name, payload})` pushes it. Any other topic is refused with `{:error, %{reason: "unknown topic"}}`.

**Revocation.** Revocation happens in another OS process, so PubSub cannot tell the server. The channel schedules `:check_key` every 30 seconds (configurable for tests); it reloads the key by id and stops with `{:stop, :normal, ...}` (and the socket's transport closes it) when the key is revoked or lost `read`. A test triggers the check directly.

**Client transport.** `src/lib/live/transport.ts` wraps `phoenix`'s `Socket` behind a small interface: `connect()`, `join(topic, onNotice)`, `onStatus(fn)` (`'live' | 'reconnecting'`), `disconnect()`. The Socket is created with `authToken: readKey()` and the default reconnect backoff. Tests replace the transport with a fake that can emit notices and status changes; the real adapter is kept thin and covered by one test against a fake `Socket` constructor.

**Mapping and coalescing.** `src/lib/live/invalidation.ts` maps a notice to query key prefixes: `event_ingested` → `['events','list']`; `delivery_changed` → `['deliveries','list']`, `['deliveries','detail', id]`, `['events','detail', event_id]`; `endpoint_changed` → endpoint lists, `endpoint(id)`, the endpoints lookup; `merchant_changed` → merchant lists, `merchant(id)`, the merchants lookup. A `Coalescer` collects prefixes and flushes them with `invalidateQueries({ queryKey, refetchType: 'active' })`: the first notice schedules a flush after 250 ms, and a prefix flushed in the last 1,000 ms waits for the end of that second; so a burst costs at most two refetches per list per second, and a single notice refetches within about 250 ms (well under 5 s).

**Lifecycle and status.** `useLiveUpdates()` runs in the `_app` layout: it connects, joins the four topics, and disconnects on unmount; `signOut` and the `401` handler also disconnect. When the status goes from `reconnecting` back to `live`, it calls `queryClient.invalidateQueries({ refetchType: 'active' })` once. A `LiveStatus` element in the layout shows "Live" or "Reconnecting…" (icon and text, `role="status"`).

**Tests.** Backend: `test/support/channel_case.ex` (new), `test/courier/notices_test.exs` (subscribe to the PubSub topics and drive ingestion, attempts, the sweeper, resend, endpoint and merchant changes), `test/courier_web/channels/dashboard_socket_test.exs` and `dashboard_channel_test.exs`. Frontend: `frontend/tests/live-updates.test.tsx` with the fake transport and MSW request counting; fake timers for the burst scenario.

## Risks / Trade-offs

- [A notice is lost while the socket is down] → the reconnect refetch covers it; notices are hints, not data.
- [Every `read` key sees every notice] → notices carry ids and statuses only, which the same key can already read over REST.
- [Many dashboard tabs multiply refetches] → each tab coalesces; acceptable for an operator dashboard.
- [A revoked key keeps receiving notices for up to 30–60 s] → only ids and statuses; accepted and stated in the spec.

## Migration Plan

No data changes. Deploying adds the `/socket` route; clients without the new SPA ignore it. Rollback: revert the change.
