# Design

## Context

`deliveries` has `resend_of_id` (nullable self-reference, indexed) and `triggered_by` (default `"system"`); the unique index on `(event_id, endpoint_id)` only covers originals (`resend_of_id IS NULL`), so any number of resends is allowed. Delivery jobs are `Courier.Delivery.Worker` jobs in `Queues.name(endpoint_id)`. The authenticated key is in `conn.assigns.current_key`. ADR "Deliveries with append-only attempts; resend creates a new delivery" applies.

## Goals / Non-Goals

**Goals:** a resend is atomic (delivery and job together), never changes history, and cannot be duplicated by concurrent requests.

**Non-Goals:** bulk resend, resending to a different endpoint, editing the payload.

## Decisions

### `Courier.Delivery.resend(delivery_id, actor)`

In one `Repo.transact/1`:

1. Lock the delivery (`FOR UPDATE`); missing or malformed id → `{:error, :not_found}`.
2. `status == "pending"` → `{:error, :delivery_in_progress}`.
3. A delivery with `resend_of_id == id and status == "pending"` exists → `{:error, :resend_in_progress}`. The lock on the original serializes concurrent resends of it, so the check is race-free.
4. Load the endpoint; disabled → `{:error, :endpoint_disabled}`.
5. Insert the new delivery: same `event_id` and `endpoint_id`, `resend_of_id: id`, `status: "pending"`, `triggered_by: actor`, `window_ends_at: now + endpoint.retry_window_seconds`.
6. Insert `Worker.new(%{delivery_id: new.id}, queue: Queues.name(endpoint_id))` with `Oban.insert/2` inside the transaction.

Returns `{:ok, new_delivery}`. `actor` is a non-empty string; the API passes `"api_key:" <> key.name` (the prefix keeps it distinct from `"system"`). A `skipped` delivery can be resent: the operator asks for it explicitly, so the endpoint's filter does not apply.

### Rendering

- `DeliveryJSON` adds `resend_of_id`, `triggered_by` and `resends` (`[%{id, status, triggered_by, inserted_at}]`, oldest first) to the show response; `get_delivery/1` preloads them.
- `EventJSON` adds `resend_of_id` to each delivery.
- `POST /api/v1/deliveries/:id/resend` renders the new delivery with the same `show` view (`attempts: []`, `resends: []`) and status `202`.

### Errors

`FallbackController`: `:delivery_in_progress` → `409 delivery_in_progress`, `:resend_in_progress` → `409 resend_in_progress`, `:endpoint_disabled` → `422 endpoint_disabled`, each with a short message.

### Logging

The controller logs at `info`: `"resend delivery=<id> new_delivery=<id> actor=<actor>"`. No payloads or secrets.

## Risks / Trade-offs

- [A resend of a delivery whose endpoint has a stopped queue] → Cannot happen: a disabled endpoint is rejected, and enabled endpoints have running queues.
- [Resend chains get long] → The read API shows one level (the delivery's direct resends and its `resend_of_id`); the UI follows links.

## Migration Plan

None.
