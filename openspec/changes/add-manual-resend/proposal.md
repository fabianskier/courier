# Proposal

## Why

When a merchant fixes a broken endpoint, or asks for an event again, an operator must be able to send a delivery once more without touching history (FR-21 to FR-23). The data model already has `resend_of_id` and `triggered_by`; this change adds the operation and its API so the dashboard (step 10) and the MCP server (step 8) can call it.

## What Changes

- **Resend**: `Courier.Delivery.resend(delivery_id, actor)` creates a new `pending` delivery for the same event and endpoint, linked to the given delivery (`resend_of_id`), with `triggered_by` set to the actor and a fresh retry window, and inserts its job in the endpoint's queue, all in one transaction. The original delivery and its attempts never change.
- **Rules**: only a terminal delivery (`succeeded`, `failed`, `skipped`) can be resent; a `pending` one gets `409 delivery_in_progress`. A delivery that already has a `pending` resend gets `409 resend_in_progress`, so a double click does not send twice. A disabled endpoint gets `422 endpoint_disabled`. A resend can itself be resent.
- **Same webhook id**: a resend is signed and sent like any delivery, with `webhook-id` equal to the event id, so receivers that deduplicate keep working.
- **API**: `POST /api/v1/deliveries/:id/resend` (scope `write`) answers `202` with the new delivery. The actor is `api_key:<key name>`. `GET /api/v1/deliveries/:id` also shows `resend_of_id`, `triggered_by` and the delivery's resends; an event's deliveries show `resend_of_id`.
- Not in this change: the dashboard action (step 10), the MCP tool (step 8), bulk resend.

## Capabilities

### New Capabilities
- `manual-resend`: resending a terminal delivery as a new linked delivery, its rules and its API.

### Modified Capabilities
- `webhook-delivery`: the delivery read API shows resend links and the actor.

## Impact

- `Courier.Delivery` (new `resend/2`), `DeliveryController`, `DeliveryJSON`, `EventJSON`, `FallbackController`, router.
- No migration (columns exist) and no new dependencies. Existing tests are not modified.
