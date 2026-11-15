# Proposal

## Why

Every other part of courier needs to know who is calling and what they may do: the producer ingests events, the dashboard and agents read data, and only some of them may resend. The accepted ADR "API keys with scopes" settles the model; nothing implements it yet, so no protected endpoint can be built.

## What Changes

- Add API keys: random secret tokens, stored only as a hash, each with a unique name and one or more scopes (`ingest`, `read`, `write`). The plaintext token is shown once, when the key is created.
- Keys can be listed (never showing the token) and revoked; a revoked key stops working at once.
- Add Mix tasks to create, list and revoke keys from the command line (`mix courier.keys.create`, `mix courier.keys.list`, `mix courier.keys.revoke`).
- Authenticate API requests with `Authorization: Bearer <token>`: missing, unknown or revoked tokens get `401`; a valid key without the scope a route needs gets `403`. Both use the API's error shape `{"error": {"code", "message"}}`.
- Add `GET /api/v1/me`, which returns the calling key's name and scopes (any scope may call it). The dashboard will use it to check a token on sign-in.
- Tokens are never logged or stored in plaintext.

## Capabilities

### New Capabilities
- `api-access`: API keys with scopes, their lifecycle (create, list, revoke) and how API requests are authenticated and authorized with them.

### Modified Capabilities
None.

## Impact

- New context `Courier.Access` with the `api_keys` table (migration).
- New web pieces: authentication and scope plugs, a fallback controller and error JSON for API errors, `GET /api/v1/me` in a new `/api/v1` scope.
- New Mix tasks under `lib/mix/tasks/`.
- No new Hex dependencies.
- The generated `CourierWeb.ErrorJSON` (router-level 404/500) keeps its current shape, because its existing test is protected; only API errors raised by controllers use the new shape.
