# Architecture

It reflects the decisions in [decisions.md](decisions.md); it changes when a decision changes.

## Overview

`courier` is a single Phoenix application (one BEAM node) backed by PostgreSQL. Oban runs inside the same node and uses the same database, so an event, its deliveries and their jobs are written in **one transaction**. A React single-page app and an MCP endpoint sit on top of the same contexts as the JSON API.

## Context

```mermaid
flowchart LR
    producer["Producer<br/>(the platform)"]
    operator["Operator<br/>(browser)"]
    agent["AI agent<br/>(Claude Code / Desktop)"]
    courier["courier<br/>webhook delivery engine"]
    merchant["Merchant endpoints<br/>(HTTPS receivers)"]

    producer -- "POST /api/v1/events<br/>ingest API key" --> courier
    operator -- "dashboard<br/>admin token" --> courier
    agent -- "MCP over Streamable HTTP<br/>read / write token" --> courier
    courier -- "signed POST<br/>(Standard Webhooks)" --> merchant
```

## Containers

```mermaid
flowchart TB
    subgraph browser["Browser"]
        spa["React SPA<br/>TypeScript, shadcn/ui, TanStack Query"]
    end

    subgraph node["courier (Phoenix, one BEAM node)"]
        api["JSON API<br/>/api/v1"]
        mcp["MCP endpoint<br/>/mcp"]
        chan["DashboardChannel<br/>/socket"]
        static["Static SPA files<br/>/"]
        ldash["LiveDashboard<br/>/admin/dashboard"]
        ctx["Contexts<br/>Ingestion, Endpoints, Delivery, Audit"]
        qm["QueueManager<br/>one queue per endpoint"]
        oban["Oban<br/>queues endpoint_ID, limit each"]
        worker["DeliveryWorker<br/>Req client, no client retries"]
    end

    db[("PostgreSQL<br/>data + Oban jobs")]
    receiver["Merchant endpoint"]
    demo["Demo receiver<br/>(compose service, can fail on purpose)"]

    spa -- "HTTPS JSON (REST)" --> api
    spa -- "WebSocket: change notices" --> chan
    spa --- static
    api --> ctx
    mcp --> ctx
    ctx -- "PubSub broadcasts" --> chan
    ctx -- "Ecto, one transaction:<br/>event + deliveries + jobs" --> db
    ctx -- "endpoint created / updated / disabled" --> qm
    qm -- "start, scale, pause, stop queue" --> oban
    oban -- "fetch jobs per queue" --> db
    oban -- "up to max_concurrency per endpoint" --> worker
    worker -- "record attempt" --> ctx
    worker -- "signed POST" --> receiver
    worker -. "local demo" .-> demo
```

Notes:

- **One deployable.** API, MCP, delivery workers and LiveDashboard run in the same release. The web layer and the MCP layer are thin adapters over the contexts in `lib/courier/`.
- **Concurrency and isolation.** Each enabled endpoint has its own Oban queue (`endpoint:<id>`) with its own limit, so deliveries run concurrently across endpoints and a slow endpoint only uses its own slots (proved by a test, see "Endpoint health"). `QueueManager` keeps the running queues in sync with the endpoints table (at boot and on every endpoint change).
- **Dashboard updates.** Contexts broadcast changes over PubSub; `DashboardChannel` forwards small notices (ids and statuses) and the SPA invalidates its TanStack Query caches, then refetches over REST.
- **Local runtime.** `docker compose up` starts `courier`, `postgres` and `demo-receiver`. Developers can also run with mise + a local Postgres.
- **SPA.** Built by Vite into `priv/static` and served by Phoenix on the same origin (no CORS). In development the Vite dev server proxies `/api` and `/socket` to Phoenix.

## Code layout (proposed)

```text
lib/courier/                 domain (contexts)
  ingestion/                 events, idempotency
  merchants/                 merchants
  endpoints/                 endpoints, filters, secrets, URL safety
  delivery/                  deliveries, worker, queue manager, backoff, signer, HTTP client
  audit/                     attempts (append-only), queries for timelines
  access/                    API keys and scopes
lib/courier_web/             thin web layer: router, controllers, JSON views, plugs
lib/courier_mcp/             thin MCP adapter: tool definitions -> context calls
frontend/                    React SPA (Vite, TypeScript, shadcn/ui)
demo/receiver/               small Plug app that verifies signatures and fails on purpose (FR-41)
docs/                        analysis, architecture, decisions
openspec/                    specs and changes
```

## Delivery lifecycle

```mermaid
stateDiagram-v2
    [*] --> skipped: endpoint filter excludes event type
    [*] --> pending: event accepted
    pending --> succeeded: 2xx
    pending --> pending: retryable failure, window open (retry scheduled)
    pending --> failed: non-retryable failure
    pending --> failed: retry window ended
    skipped --> [*]
    succeeded --> [*]
    failed --> [*]
```

A resend never changes these states: it creates a **new** delivery (`resend_of_id` → original) that starts at `pending`.

## Sequence: happy path

```mermaid
sequenceDiagram
    autonumber
    participant P as Producer
    participant API as JSON API
    participant ING as Ingestion context
    participant DB as PostgreSQL
    participant W as DeliveryWorker (Oban)
    participant M as Merchant endpoint

    P->>API: POST /api/v1/events (Idempotency-Key, ingest key)
    API->>ING: ingest(attrs, key)
    ING->>DB: BEGIN, insert event (unique key)<br/>insert delivery per endpoint (pending or skipped)<br/>insert Oban job per pending delivery<br/>(in queue endpoint_ID), COMMIT
    ING-->>API: {:ok, event}
    API-->>P: 202 {event_id}
    DB-->>W: job available
    W->>DB: load delivery, endpoint, event
    W->>M: POST payload<br/>webhook-id, webhook-timestamp, webhook-signature,<br/>courier-delivery-id
    M-->>W: 200 OK
    W->>DB: insert attempt (append-only)<br/>update delivery to succeeded, reset endpoint failure count
    W-->>W: emit telemetry
```

Repeat with the same key and body: step 3 hits the unique constraint, the transaction rolls back, and the API returns `200` with the original event (FR-2). Same key with a different body → `422` (FR-3).

## Sequence: failure path (retries, then dead letter)

```mermaid
sequenceDiagram
    autonumber
    participant W as DeliveryWorker (Oban)
    participant DB as PostgreSQL
    participant M as Merchant endpoint
    participant O as Operator / agent

    loop while the retry window is open
        W->>M: signed POST (attempt n)
        M-->>W: 503 / timeout / connection refused
        W->>DB: insert attempt n (status, duration, error)<br/>increment endpoint consecutive failures
        alt failures reach the threshold (default 20)
            W->>DB: mark endpoint degraded
            W-->>W: telemetry: endpoint degraded
        end
        W->>W: next = backoff(n) with jitter,<br/>or Retry-After if present
        W-->>DB: snooze job until next (if next < window end)
    end
    W->>DB: delivery = failed (dead letter)
    W-->>W: telemetry: delivery failed

    O->>DB: resend(delivery_id) via dashboard or MCP (write scope)
    DB-->>O: new delivery (pending, resend_of_id = original, triggered_by = actor)
    Note over W,M: the new delivery follows the happy path or this one,<br/>the original and its attempts stay unchanged
```

A non-retryable result (for example `400`, `404` or a `3xx`) skips the loop: one attempt is stored and the delivery becomes `failed` at once.

## Retry timing

- Attempt `n` (starting at 1) waits `random(0, min(cap, base * 2^(n-1)))` with base 10 s and cap 1 h, plus a small floor, unless `Retry-After` asks for longer (bounded by the cap).
- The worker computes the next run time itself and **snoozes** the Oban job. It does not rely on Oban's `max_attempts` to end retries: the **retry window** (`delivery.inserted_at + endpoint.retry_window`) is the only stop rule, so the policy is easy to test and to show in the UI ("next attempt at …", "gives up at …").
- In Oban 2.24 a snooze does not consume an attempt (it only increments `meta.snoozed`), so `max_attempts` stays a safety net, not the policy.
- Req runs with `retry: false` and explicit `connect` and `receive` timeouts. Oban is the only layer that retries.
- The HTTP connection pool per endpoint origin is at least the endpoint's `max_concurrency`, so the pool never becomes a hidden second limit.

## Data model sketch

```mermaid
erDiagram
    API_KEY {
        uuid id
        string name
        string key_hash
        string[] scopes "ingest | read | write"
        timestamp revoked_at
    }
    MERCHANT ||--o{ ENDPOINT : has
    MERCHANT ||--o{ EVENT : "is the subject of"
    EVENT ||--o{ DELIVERY : "fans out to"
    ENDPOINT ||--o{ DELIVERY : receives
    DELIVERY ||--o{ ATTEMPT : "is tried by"
    DELIVERY |o--o{ DELIVERY : "resend_of"

    MERCHANT {
        uuid id
        string name
        bool enabled
        timestamp inserted_at
    }
    ENDPOINT {
        uuid id
        uuid merchant_id
        string url
        string description
        string[] event_types "exact or prefix.*, empty = all"
        binary secret_encrypted
        binary previous_secret_encrypted
        timestamp previous_secret_expires_at
        int retry_window_seconds "max 86400"
        bool retry_on_4xx
        bool enabled
        int max_concurrency "Oban queue limit, default 10"
        int consecutive_failures
        timestamp degraded_at
    }
    EVENT {
        uuid id "sent as webhook-id"
        string idempotency_key "unique"
        string request_hash "detects key reuse"
        uuid merchant_id
        string type
        jsonb payload
        timestamp occurred_at
        timestamp inserted_at
    }
    DELIVERY {
        uuid id "sent as courier-delivery-id"
        uuid event_id
        uuid endpoint_id
        string status "pending | succeeded | failed | skipped"
        int attempt_count
        timestamp next_attempt_at
        timestamp window_ends_at
        uuid resend_of_id
        string triggered_by "system | api_key:NAME"
        timestamp completed_at
    }
    ATTEMPT {
        uuid id
        uuid delivery_id
        int number
        timestamp started_at
        int duration_ms
        string url
        jsonb request_headers "redacted"
        int response_status
        text response_body "first 4 KB"
        string error
    }
```

Key constraints:

- `events.idempotency_key` unique. One producer in v1, so the key is global.
- `deliveries (event_id, endpoint_id)` unique **where `resend_of_id` is null**: one original delivery per endpoint, any number of resends.
- `attempts (delivery_id, number)` unique. The application only ever inserts rows; a database trigger rejects `UPDATE` on `attempts`, and `DELETE` unless the transaction set `courier.retention = on`, which only the retention job does (FR-19, FR-37).
- Delivery status changes only forward (`pending` → terminal), enforced in the context and checked by a test.

## API surface (sketch)

| Method and path | Scope | Purpose |
|---|---|---|
| `POST /api/v1/events` | ingest | Ingest an event (FR-1 to FR-5) |
| `GET /api/v1/events`, `GET /api/v1/events/:id` | read | List and show events |
| `GET /api/v1/deliveries`, `GET /api/v1/deliveries/:id` | read | List (filters, cursor) and show with attempts |
| `POST /api/v1/deliveries/:id/resend` | write | Manual resend (FR-21 to FR-23) |
| `GET/POST/PATCH /api/v1/merchants[/:id]` | read / write | Merchants |
| `GET/POST/PATCH /api/v1/endpoints[/:id]`, `POST /api/v1/endpoints/:id/rotate_secret` | read / write | Endpoints, filters, secrets |
| `POST /mcp` | read / write | MCP (Streamable HTTP) |
| `/socket` (WebSocket), topics `deliveries`, `endpoints` | read | Dashboard change notices (Phoenix Channels) |

Errors follow one JSON shape: `{"error": {"code": "...", "message": "...", "details": {...}}}`.

## Authentication

Every request to `/api/v1` must carry an API key in the `Authorization` header:

```
Authorization: Bearer ck_...
```

Tokens start with `ck_` followed by 32 bytes of secure randomness. Only a SHA-256 hash is stored; the plaintext is printed once, when the key is created.

**Scopes.** Each key holds one or more of `ingest` (send events), `read` (query data) and `write` (change data, resend). Each route declares the scope it needs; scopes are independent, so `write` does not imply `read`.

**Errors.** API errors share one shape, with `details` only when there are field errors:

```json
{"error": {"code": "unauthorized", "message": "A valid API key is required."}}
```

| Situation | Status | Code |
|---|---|---|
| Missing or malformed header, unknown token, revoked key | `401` (with `www-authenticate: Bearer`) | `unauthorized` |
| Valid key without the route's scope | `403` | `forbidden` |
| Resource not found | `404` | `not_found` |
| Invalid input (field errors in `details`) | `422` | `invalid` |

Error responses never echo the token, and tokens are never logged.

**Managing keys.** Keys are managed from the command line:

```sh
mix courier.keys.create --name dashboard --scopes read,write   # prints the token once
mix courier.keys.list                                          # name, scopes, created, status; never tokens
mix courier.keys.revoke dashboard                              # stops working at once, stays listed
```

**Checking a token.** `GET /api/v1/me` works with any active key, whatever its scopes, and returns the key's name and scopes. The dashboard uses it to check a token on sign-in.

```sh
curl -s http://localhost:4000/api/v1/me -H "Authorization: Bearer $COURIER_TOKEN"
# {"name":"dashboard","scopes":["read","write"]}
```

`mix courier.keys.*` raise their own process's log level to at least `:info` before starting the app, so Ecto's debug SQL lines are not printed; a stricter global level is kept and the rest of the system logs as configured.

## Merchants and endpoints

**Merchants** (`Courier.Merchants`) own endpoints and events. A merchant has a name (1 to 255 characters, trimmed, not unique) and an `enabled` flag. Merchants are never deleted; disabling one does not change its endpoints' own `enabled` flags.

**Endpoints** (`Courier.Endpoints`) belong to a merchant and hold:

| Field | Default | Rule |
|---|---|---|
| `url` | | must pass the URL policy below |
| `description` | `null` | free text |
| `event_types` | `[]` | up to 50 unique patterns |
| `enabled` | `true` | |
| `retry_window_seconds` | `86400` | 60 to 86400 |
| `retry_on_4xx` | `false` | |
| `max_concurrency` | `10` | 1 to 50 (the endpoint's Oban queue limit) |

Endpoints are never deleted. An unknown `merchant_id` on create is a field error (`422`), not a `404`.

**Event-type filters** (`Courier.Endpoints.EventFilter`). A pattern is an exact type of dot-separated lowercase segments (`payment.succeeded`) or such a prefix followed by `.*` (`payment.*`). `*` alone, uppercase, inner wildcards and empty strings are rejected. An empty list matches every type; `payment.*` matches `payment.succeeded` and `payment.card.declined` but not `payments.created`.

**URL policy** (`Courier.Endpoints.URLPolicy`). `check(url, opts)` is pure apart from DNS and is reused by delivery, which re-checks before every request. A URL is accepted when:

1. its scheme is `https` (or `http` where `require_https: false`), it has a host and no user info;
2. its host is on `allowed_hosts` (case-insensitive), **or** every address it resolves to (IP literal or DNS, IPv4 and IPv6) is public. Blocked: `0.0.0.0/8`, `10.0.0.0/8`, `100.64.0.0/10`, `127.0.0.0/8`, `169.254.0.0/16`, `172.16.0.0/12`, `192.0.0.0/24`, `192.168.0.0/16`, `198.18.0.0/15`, `224.0.0.0/4`, `240.0.0.0/4`, `::/96`, `fc00::/7`, `fe80::/10`, `ff00::/8`; IPv4-mapped (`::ffff:0:0/96`) and NAT64 (`64:ff9b::/96`) addresses are checked as their embedded IPv4. A host that does not resolve is rejected.

Any failure becomes one field error, `url: "must be a public https URL"`, which never echoes resolved addresses. Configuration (`config :courier, Courier.Endpoints.URLPolicy`): production uses `require_https: true, allowed_hosts: []`; development allows `http` and `localhost`, `127.0.0.1` and `demo-receiver`; tests use `Courier.Endpoints.TestResolver`, which resolves by naming convention (`*.public.test`, `*.private.test`, `*.v6private.test`) and never touches the network.

**Signing secrets.** Each endpoint gets `"whsec_" <> Base.encode64(32 random bytes)` (Standard Webhooks format). The secret is returned only by `POST /api/v1/endpoints` and `POST /api/v1/endpoints/:id/rotate_secret`; no other response, log line or `inspect/1` output contains it.

**Rotation.** Rotating moves the current secret to `previous_secret`, stores a new one and sets `previous_secret_expires_at` to now + 24 h. `Courier.Endpoints.signing_secrets/2` returns `[secret, previous_secret]` during that overlap and `[secret]` after it, so receivers can switch without losing webhooks. Rotating again during an overlap replaces the previous secret with the current one.

**Encryption at rest.** `secret` and `previous_secret` use `Courier.Encrypted.Binary` (`Cloak.Ecto.Binary`) through `Courier.Vault` (`Cloak.Ciphers.AES.GCM`, AES-256-GCM, tag `AES.GCM.V1`). The key comes from `COURIER_ENCRYPTION_KEY`, the base64 encoding of 32 random bytes (`openssl rand -base64 32`). It is required in production: boot fails with a clear message when it is missing or not 32 bytes. Development and test use fixed, non-secret keys written in their config files. Losing the key makes stored secrets unreadable; after restoring with a new key, rotate every endpoint's secret.

**Pagination** (`Courier.Pagination`). List endpoints take `limit` (default 50, 1 to 100) and an opaque `cursor`, and answer `{"data": [...], "next_cursor": "..."}`, with `next_cursor` `null` on the last page. Pagination is keyset on `(inserted_at, id)` ascending, so items are oldest first and pages do not repeat or skip rows when new ones are inserted. The cursor is URL-safe base64 of the last item's timestamp and id; an invalid `limit` or a cursor the system did not issue returns `422 invalid`. `GET /api/v1/endpoints` also accepts `merchant_id` and `degraded` (see "Endpoint health").

```sh
curl -s -X POST http://localhost:4000/api/v1/endpoints -H "Authorization: Bearer $COURIER_TOKEN" \
  -H "content-type: application/json" \
  -d '{"merchant_id": "<id>", "url": "https://hooks.example.com/courier", "event_types": ["payment.*"]}'
# {"data": {"id": "...", "enabled": true, "retry_window_seconds": 86400, ..., "secret": "whsec_..."}}
```

## Event ingestion

`Courier.Ingestion` accepts events from the producer, deduplicates them by idempotency key and stores each one with its deliveries (`Courier.Delivery`) in one transaction.

**Request.** `POST /api/v1/events` needs a key with the `ingest` scope.

| Part | Rule |
|---|---|
| `Authorization` header | `Bearer ck_...` with the `ingest` scope |
| `Idempotency-Key` header | required; 1 to 255 printable ASCII characters (`0x21` to `0x7E`, no spaces) |
| `type` | dot-separated lowercase segments of letters, digits and `_` (`payment.succeeded`); no wildcards |
| `merchant_id` | an existing, enabled merchant |
| `payload` | a JSON object, at most 256 KB (262 144 bytes) when encoded as JSON |
| `occurred_at` | optional ISO 8601 timestamp; defaults to the time of receipt |

Other body fields are ignored. `Plug.Parsers` also rejects any request body over 1 MB before it reaches the controller.

```sh
curl -s -X POST http://localhost:4000/api/v1/events -H "Authorization: Bearer $COURIER_INGEST_TOKEN" \
  -H "content-type: application/json" -H "Idempotency-Key: pay_123-succeeded" \
  -d '{"type": "payment.succeeded", "merchant_id": "<id>", "payload": {"payment_id": "pay_123", "amount": 1000}}'
# 202 {"data": {"id": "...", "type": "payment.succeeded", "merchant_id": "<id>", "payload": {...},
#      "occurred_at": "2026-11-15T10:00:00.123456Z", "received_at": "2026-11-15T10:00:00.123456Z",
#      "deliveries": [{"id": "...", "endpoint_id": "...", "status": "pending", "window_ends_at": "2026-11-16T10:00:00.123456Z",
#                      "resend_of_id": null}]}}
```

**Responses.**

| Situation | Status | Code |
|---|---|---|
| New event stored | `202` | |
| Repeat of a stored event (see below) | `200` | |
| Key without the `ingest` scope | `403` | `forbidden` |
| Missing or malformed `Idempotency-Key`, invalid `type`, non-object `payload`, malformed `occurred_at`, unknown `merchant_id` (field errors in `details`) | `422` | `invalid` |
| Merchant exists but is disabled | `422` | `merchant_disabled` |
| Key already used with a different request | `422` | `idempotency_key_reused` |
| `payload` over 256 KB as JSON | `413` | `payload_too_large` |

Rejected requests store nothing. Validation runs before the idempotency check, so a repeat that is now invalid is rejected like a new request. One exception: when the merchant was disabled after the original was stored, a request with the same key is answered as for an enabled merchant (`200` with the original event for a repeat, `422 idempotency_key_reused` for a different body), so a producer's retry does not see a misleading `merchant_disabled`.

**Idempotency.** Keys are global (one producer in v1). When a key matches a stored event, courier compares a SHA-256 hash of the request's `type`, `merchant_id`, `payload` and `occurred_at` **as sent**:

- Same hash: the request is a repeat. It answers `200` with the original event and its deliveries and stores nothing new. Key order inside `payload` does not matter.
- Different hash: `422 idempotency_key_reused`, and the stored event is unchanged.

A repeat must therefore send the same `occurred_at` as the original: if the original omitted it and the retry sends the time the server assigned (or the other way round), the request counts as a different body. Producers should retry with exactly the same request. Concurrent requests with the same key resolve to one event: the insert uses `ON CONFLICT DO NOTHING` on the unique key, the loser waits for the winner to commit and then answers with the winner's event.

**Fan-out.** In the same transaction as the event, courier creates one delivery per **enabled** endpoint of the merchant; disabled endpoints get none, and a merchant without enabled endpoints gets an event with no deliveries (still `202`).

| Delivery status | When | Fields |
|---|---|---|
| `pending` | the endpoint's event-type filters match the type (an empty list matches every type) | `window_ends_at` = `received_at` + the endpoint's `retry_window_seconds` |
| `skipped` | the filters do not match | `window_ends_at` is `null`; `completed_at` = `received_at` |
| `succeeded`, `failed` | set by delivery (see "Webhook delivery") | |

The same transaction also inserts one Oban job per pending delivery, in the endpoint's queue. If storing the event, any delivery or any job fails, the whole transaction rolls back and none of them exists. An event's deliveries are always listed in the same order (the ingestion response, a repeat and a read): by endpoint creation, then by delivery creation.

**Reading events.** Needs the `read` scope.

- `GET /api/v1/events` lists events **newest first** with the same `limit`/`cursor` pagination as other lists (keyset on `(inserted_at, id)` descending). Filters: `merchant_id` (a malformed id returns an empty page) and `type` (exact match, no wildcards). Items do not include deliveries.
- `GET /api/v1/events/:id` returns the event with its deliveries (`id`, `endpoint_id`, `status`, `window_ends_at`, `resend_of_id`), resends included (see "Manual resend"). An unknown or malformed id returns `404 not_found`.

The idempotency key and request hash are stored but never returned.

```sh
curl -s "http://localhost:4000/api/v1/events?merchant_id=<id>&type=payment.succeeded&limit=20" \
  -H "Authorization: Bearer $COURIER_TOKEN"
# {"data": [{"id": "...", "type": "payment.succeeded", ...}], "next_cursor": null}

curl -s http://localhost:4000/api/v1/events/<event_id> -H "Authorization: Bearer $COURIER_TOKEN"
# {"data": {"id": "...", ..., "deliveries": [{"id": "...", "endpoint_id": "...", "status": "skipped", "window_ends_at": null, "resend_of_id": null}]}}
```

## Webhook delivery

`Courier.Delivery.Worker` sends each pending delivery to its endpoint, retries it until it succeeds, fails for good or its retry window ends, and records every attempt (`Courier.Audit`). The decisions are pure modules tested on their own (`Signer`, `RetryPolicy`); the worker only wires them together with the HTTP client (`Client`) and `Courier.Delivery.record_attempt/3`.

**Request.** Each attempt is a `POST` to the endpoint URL with a JSON body, encoded once per attempt so the signature covers exactly the bytes sent:

```json
{"id": "<event id>", "type": "payment.succeeded", "timestamp": "2026-11-15T10:00:00.123456Z",
 "merchant_id": "<merchant id>", "data": {"payment_id": "pay_123", "amount": 1000}}
```

`timestamp` is the event's `occurred_at` and `data` its payload.

| Header | Value |
|---|---|
| `content-type` | `application/json` |
| `user-agent` | `courier/<version>` |
| `webhook-id` | the event id: the same for every attempt and every endpoint, so receivers deduplicate by it |
| `webhook-timestamp` | Unix seconds when the attempt started |
| `webhook-signature` | `v1,<base64 signature>`, one per signing secret, space-separated |
| `courier-delivery-id` | the delivery id, for support and the read API |

**Verifying the signature** (Standard Webhooks). For each secret, the signature is `base64(HMAC-SHA256(key, "<webhook-id>.<webhook-timestamp>.<raw body>"))`, where `key` is the base64-decoded part of the secret after `whsec_`. During the 24 h after a rotation the header holds two signatures (new secret first, then the previous one); a receiver accepts the request when any `v1,` signature matches one of the secrets it knows. A receiver should:

1. read the raw body before parsing it as JSON;
2. reject a `webhook-timestamp` more than a few minutes away from its own clock (replay protection);
3. compute the signature and compare it in constant time with each `v1,` entry;
4. deduplicate by `webhook-id`, because delivery is at least once.

The official Standard Webhooks libraries (`standardwebhooks` for JavaScript, Python, Go, Ruby, PHP and others) do all of this. In Elixir:

```elixir
"whsec_" <> encoded = secret
expected = :crypto.mac(:hmac, :sha256, Base.decode64!(encoded), "#{id}.#{timestamp}.#{raw_body}") |> Base.encode64()

signature_header
|> String.split(" ")
|> Enum.any?(fn "v1," <> sig -> Plug.Crypto.secure_compare(sig, expected); _ -> false end)
```

**HTTP client** (`Courier.Delivery.Client`). Req with `retry: false` (Oban is the only layer that retries), redirects not followed, a 5 s connect timeout and a 15 s receive timeout. The response body is streamed and reading stops after its first 4096 bytes, which closes the connection, so a large body never sits in memory. Each request runs in a task under `Courier.Delivery.TaskSupervisor` with a total deadline of 30 s, from connect to the end of reading; a request still running at the deadline is killed and recorded as error `timeout` (retried), so a body that trickles in cannot hold a queue slot. Requests go through the `Courier.Finch` pool, which keeps one pool of 50 connections per origin, as large as the largest allowed `max_concurrency`. The URL policy runs again before every request (see "Merchants and endpoints").

**Outcome of an attempt.**

| Result | Outcome |
|---|---|
| `2xx` | delivery `succeeded`, `completed_at` set |
| network error, timeout, `408`, `429`, `5xx` | retried |
| another `4xx` | retried if the endpoint has `retry_on_4xx`, else `failed` |
| `3xx` | `failed` (the `location` is never requested) |
| host now resolves to a non-public address | attempt with error `url_rejected: <reason>`, no request, `failed` |
| host does not resolve | attempt with error `dns: unresolvable_host`, retried |
| endpoint disabled when the job runs | no attempt, job snoozed 60 s |

A delivery's status only moves forward, from `pending` to `succeeded` or `failed`. A result that arrives for a delivery that is no longer `pending` (for example, a job that ran twice) stores nothing and changes nothing.

**Retry timing** (`Courier.Delivery.RetryPolicy`). After attempt `n`, the next one waits `1 + random(0, min(3600, 10 × 2^(n-1)))` seconds: up to 11 s after the first attempt, 21 s after the second, and at most about an hour from the ninth on. On `429` and `503`, a `Retry-After` header (delta seconds or HTTP date) is honoured when it asks for longer, capped at 3600 s. The worker stores the next time in `next_attempt_at` and snoozes the Oban job until then; snoozes do not consume Oban attempts, so `max_attempts: 10` only guards against crashes. When the next attempt would start at or after `window_ends_at` (received time + the endpoint's `retry_window_seconds`), the delivery becomes `failed` (dead letter). A job that runs after the window ended marks its delivery `failed` without sending anything.

**Attempts** (`Courier.Audit.Attempt`, table `attempts`). Every attempt, including a rejected URL, is one row: `number` (1, 2, … per delivery, unique), `started_at`, `duration_ms`, `url`, `request_headers` (every header sent, with `webhook-signature` stored as `[redacted]`), `response_status`, `response_body` (first 4096 bytes, invalid UTF-8 and NUL bytes replaced) and `error`. The attempt and the delivery's new state are written in one transaction that locks the delivery row; the lock is never held during the HTTP request. A database trigger, `attempts_append_only()`, rejects every `UPDATE` and every `DELETE` unless the transaction ran `SET LOCAL courier.retention = on`, which only the retention job will do.

**Queues per endpoint** (`Courier.Delivery.QueueManager`). Each enabled endpoint has its own Oban queue `endpoint:<endpoint id>` with a limit of the endpoint's `max_concurrency`, so a slow endpoint only uses its own share of concurrency. The manager starts after Oban and starts the queues of all enabled endpoints at boot. Creating or enabling an endpoint starts its queue, changing `max_concurrency` scales it, and disabling it stops it; the pending deliveries of a disabled endpoint keep their jobs and resume when it is enabled again (until their windows end, when the window sweeper fails them). Queue limits are per node, which matches the single node of v1.

**Window sweeper** (`Courier.Delivery.WindowSweeper`). A delivery normally reaches a terminal state in its own job, but the job of a disabled endpoint never runs (its queue is stopped), and a job can be lost. `Oban.Plugins.Cron` therefore runs the sweeper every 5 minutes (`*/5 * * * *`) in `maintenance`, the only static Oban queue (limit 1). Each run takes up to 500 `pending` deliveries with `window_ends_at <= now`, oldest first, cancels their delivery jobs (`Oban.cancel_all_jobs/1`, matched by the `delivery_id` job argument) and marks each one `failed` with `completed_at` set and **no attempt** (`Courier.Delivery.fail_without_attempt/2`). Jobs are cancelled first, so a run that crashes in between leaves the deliveries `pending` for the next run. A full batch makes the sweeper insert itself again to continue at once. Pending deliveries inside their window and terminal deliveries are never touched. A delivery failed by the sweeper stays failed even if its endpoint is enabled again later; a resend is the way to deliver it.

**Reading a delivery.** `GET /api/v1/deliveries/:id` needs the `read` scope and returns the delivery with its resend links (`resend_of_id`, `triggered_by` and `resends`, see "Manual resend") and its attempts in order. Request headers are never returned. An unknown or malformed id returns `404 not_found`.

```sh
curl -s http://localhost:4000/api/v1/deliveries/<delivery_id> -H "Authorization: Bearer $COURIER_TOKEN"
# {"data": {"id": "...", "event_id": "...", "endpoint_id": "...", "status": "succeeded", "attempt_count": 2,
#   "next_attempt_at": null, "window_ends_at": "2026-11-16T10:00:00.123456Z", "completed_at": "2026-11-15T10:00:12.401234Z",
#   "resend_of_id": null, "triggered_by": "system", "resends": [],
#   "attempts": [
#     {"number": 1, "started_at": "2026-11-15T10:00:00.200000Z", "duration_ms": 87, "url": "https://hooks.example.com/courier",
#      "response_status": 503, "response_body": "unavailable", "error": null},
#     {"number": 2, "started_at": "2026-11-15T10:00:12.300000Z", "duration_ms": 95, "url": "https://hooks.example.com/courier",
#      "response_status": 200, "response_body": "ok", "error": null}]}}
```

## Endpoint health

Operators need to see which endpoints are failing before merchants complain (FR-17), and a failing endpoint must not slow down the others (FR-36).

**Counting.** Each endpoint has `consecutive_failures`: the number of attempts that did not get a `2xx` since its last success. `Courier.Delivery.record_attempt/3` updates it in the **same transaction** that stores the attempt and the delivery's new state, so the count changes exactly once per stored attempt:

| Attempt | Effect on the endpoint |
|---|---|
| `2xx` | `consecutive_failures` = 0, `degraded_at` cleared |
| anything else that stores an attempt (status not `2xx`, network error, timeout, rejected URL, unresolvable host), retried or not | `consecutive_failures` + 1 |
| no attempt stored (window ended, sweeper, stale result, endpoint disabled when the job runs) | nothing |

The transaction locks the delivery row first and the endpoint row second (`SELECT ... FOR UPDATE`), always in that order, so concurrent attempts of one endpoint serialize briefly on the endpoint row and cannot deadlock. The cost is one short `UPDATE` per attempt, bounded by the endpoint's `max_concurrency`.

**Degraded flag.** When the count reaches the threshold and the endpoint is not yet degraded, `degraded_at` is set to the current time. The next successful attempt clears it. Being degraded is only a signal: the queue is not paused, and deliveries keep retrying inside their windows as usual.

**Threshold.** One global value, 20 by default:

```elixir
config :courier, :degraded_threshold, 20
```

It is read on each failed attempt (`Courier.Delivery.degraded_threshold/0`) and must be a positive integer; anything else raises an `ArgumentError`. There is no per-endpoint threshold. Changing the value does not re-evaluate endpoints at once: an endpoint already degraded stays so until its next success, and one at or above a lowered threshold becomes degraded on its next failure.

**Telemetry.** Events are emitted after the transaction commits, so a rolled-back change emits nothing, and once per transition: further failures of a degraded endpoint emit nothing new.

| Event | Measurements | Metadata |
|---|---|---|
| `[:courier, :endpoint, :degraded]` | `%{consecutive_failures: n}` | `%{endpoint_id: id, merchant_id: id}` |
| `[:courier, :endpoint, :recovered]` | `%{}` | `%{endpoint_id: id, merchant_id: id}` |

Their metrics are on the admin dashboard (see "Observability").

**API.** Every endpoint response includes its health, and the list can be filtered by it:

| Field | Meaning |
|---|---|
| `consecutive_failures` | failed attempts since the last success |
| `degraded` | `true` when `degraded_at` is set |
| `degraded_at` | when the endpoint became degraded, or `null` |

`GET /api/v1/endpoints?degraded=true` lists only degraded endpoints and `degraded=false` only those that are not; any other value is ignored. The filter combines with `merchant_id` and pagination. The fields are read-only: no request can set them.

```sh
curl -s "http://localhost:4000/api/v1/endpoints?degraded=true" -H "Authorization: Bearer $COURIER_TOKEN"
# {"data": [{"id": "...", "url": "https://hooks.example.com/courier", ..., "consecutive_failures": 23,
#            "degraded": true, "degraded_at": "2026-11-16T09:12:44.512345Z"}], "next_cursor": null}
```

**Isolation guarantee.** An endpoint that is slow on every request does not delay the first attempt of another endpoint's delivery, because each endpoint's jobs run in its own Oban queue with its own limit (see "Queues per endpoint") and the HTTP pool is per origin. `test/courier/delivery/endpoint_isolation_test.exs` proves it with real Oban queues and real HTTP servers on loopback: one endpoint takes 3 s to answer and has 6 jobs for a limit of 2; a delivery then created for another endpoint succeeds in under 2 s, while the slow endpoint still has 2 jobs executing, 4 waiting in its own queue and none finished. This is the test the queue ADR asks for. The guarantee is per node, like the queue limits.

## Manual resend

When a merchant fixes a broken endpoint, or asks for an event again, an operator sends a delivery once more without touching history (FR-21 to FR-23). `Courier.Delivery.resend/2` never changes the resent delivery: it creates a **new** delivery linked to it.

**Request.** `POST /api/v1/deliveries/:id/resend` needs a key with the `write` scope and takes no body. It answers `202` with the new delivery, in the same shape as `GET /api/v1/deliveries/:id` (no attempts and no resends yet).

**What a resend creates.** In one transaction, so either all of it exists or none:

- a new `pending` delivery for the same event and endpoint, with `resend_of_id` set to the resent delivery, `triggered_by` set to the actor and `window_ends_at` = now + the endpoint's `retry_window_seconds` (a fresh retry window);
- its delivery job in the endpoint's queue (`endpoint:<endpoint id>`).

From there it is a delivery like any other: same worker, signature, retries, attempts and effect on endpoint health. Its requests carry `webhook-id` equal to the **event id**, as the original did, so receivers that deduplicate by it keep working, and `courier-delivery-id` equal to the new delivery's id. The resent delivery keeps its status, `completed_at`, attempt count and attempts.

**Rules.** The checks run in the order of the table, and a rejected request creates nothing.

| Situation | Status | Code |
|---|---|---|
| Key without the `write` scope | `403` | `forbidden` |
| Unknown or malformed delivery id | `404` | `not_found` |
| Delivery is `pending` | `409` | `delivery_in_progress` |
| Delivery already has a `pending` resend | `409` | `resend_in_progress` |
| The delivery's endpoint is disabled | `422` | `endpoint_disabled` |
| Otherwise: the delivery is `succeeded`, `failed` or `skipped` | `202` | |

- A `skipped` delivery can be resent: the operator asks for it explicitly, so the endpoint's event-type filter does not apply.
- A resend can itself be resent once it is terminal; the new delivery's `resend_of_id` is that resend, not the first original.
- `resend_in_progress` only looks at the delivery's **direct** resends, and only while one is `pending`: after it succeeds or fails, the delivery can be resent again. This is what makes a double click send once.
- The transaction locks the resent delivery's row (`SELECT ... FOR UPDATE`) before checking, so concurrent resends of one delivery serialize and create at most one new delivery; the others get `409 resend_in_progress`.
- There is no bulk resend, no resend to a different endpoint and no payload editing.

**Actor.** `triggered_by` records who caused a delivery: `system` for deliveries created by ingestion, and `api_key:<key name>` for a resend through the API (for example `api_key:dashboard`). The prefix keeps a key that happens to be named `system` distinct. Each accepted resend is also logged at `info` as `resend delivery=<id> new_delivery=<id> actor=<actor>`, without payloads or secrets.

**Links in the read API.** Both directions are visible, one level at a time:

| Response | Field | Meaning |
|---|---|---|
| `GET /api/v1/deliveries/:id` | `resend_of_id` | the delivery this one resends, or `null` for an original |
| | `triggered_by` | the actor, as above |
| | `resends` | its direct resends, oldest first: `id`, `status`, `triggered_by`, `inserted_at` |
| `GET /api/v1/events/:id`, ingestion responses | `deliveries[].resend_of_id` | the same, for each of the event's deliveries (originals and resends) |

A chain (a resend of a resend) is followed link by link: each delivery shows only its own `resend_of_id` and its direct resends.

```sh
curl -s -X POST http://localhost:4000/api/v1/deliveries/<delivery_id>/resend -H "Authorization: Bearer $COURIER_TOKEN"
# 202 {"data": {"id": "<new_id>", "event_id": "...", "endpoint_id": "...", "status": "pending", "attempt_count": 0,
#   "next_attempt_at": null, "window_ends_at": "2026-11-17T09:30:00.123456Z", "completed_at": null,
#   "resend_of_id": "<delivery_id>", "triggered_by": "api_key:dashboard", "resends": [], "attempts": []}}

# again, while the first resend is still pending
curl -s -X POST http://localhost:4000/api/v1/deliveries/<delivery_id>/resend -H "Authorization: Bearer $COURIER_TOKEN"
# 409 {"error": {"code": "resend_in_progress", "message": "The delivery already has a pending resend."}}

curl -s http://localhost:4000/api/v1/deliveries/<delivery_id> -H "Authorization: Bearer $COURIER_TOKEN"
# {"data": {"id": "<delivery_id>", "status": "failed", ..., "resend_of_id": null, "triggered_by": "system",
#   "resends": [{"id": "<new_id>", "status": "pending", "triggered_by": "api_key:dashboard",
#                "inserted_at": "2026-11-16T09:30:00.123456Z"}],
#   "attempts": [...]}}
```

The dashboard action (step 10) and the MCP tool `resend_delivery` (step 8) will call the same function with their own actor.

## Observability

Operators see what courier is doing without reading the database (FR-33, FR-34): courier emits telemetry events, `CourierWeb.Telemetry` turns them into metrics, and Phoenix LiveDashboard shows them to an admin.

**Events.** All are under `[:courier, ...]`, and their names live in `Courier.Telemetry`. Events about a change are emitted after the transaction commits and once per change, so a rolled-back change, a repeated event or a stale result emits nothing. Measurements and metadata hold counts, durations and ids only: never payloads, response bodies, headers or secrets.

| Event | Measurements | Metadata | Emitted by |
|---|---|---|---|
| `[:courier, :event, :ingested]` | `deliveries`, `pending` | `merchant_id`, `type` | `Courier.Ingestion`, new events only |
| `[:courier, :attempt, :start]` | `system_time`, `monotonic_time` | `delivery_id`, `endpoint_id`, `number` | the worker, before the request |
| `[:courier, :attempt, :stop]` | `duration` (native units), `since_created_ms` | the start metadata plus `outcome` (`success`, `retry`, `give_up`), `status` (integer or `nil`), `status_class` (`2xx`… or `error`) | the worker, after the request |
| `[:courier, :attempt, :exception]` | `duration` | the start metadata plus `kind`, `reason`, `stacktrace` | the worker, if the request raises |
| `[:courier, :delivery, :succeeded]` | `attempts`, `total_ms` | `delivery_id`, `endpoint_id` | `Courier.Delivery.record_attempt/3` |
| `[:courier, :delivery, :failed]` | `attempts`, `total_ms` | the above plus `reason` (`non_retryable`, `window_ended`) | `record_attempt/3`, `fail_without_attempt/2` |
| `[:courier, :delivery, :retry_scheduled]` | `delay_seconds` | `delivery_id`, `endpoint_id`, `attempt` | `record_attempt/3` |
| `[:courier, :endpoint, :degraded]`, `[:courier, :endpoint, :recovered]` | see "Endpoint health" | `endpoint_id`, `merchant_id` | `record_attempt/3` |
| `[:courier, :queue, :lag]` | `seconds`, `available` | `queue` | `Courier.Delivery.QueueLag`, every 10 s |

`since_created_ms` is the time from the delivery's creation to the start of the attempt; for attempt 1 it is the time to first attempt (the NFR target). `total_ms` is the time from creation to `completed_at`. The attempt events come from one `:telemetry.span/3`, so `start` and `stop` (or `exception`) always pair up.

**Queue lag.** `Courier.Delivery.QueueLag.measure/0` is a periodic measurement of `CourierWeb.Telemetry`'s poller (every 10 s). One query groups the jobs in state `available` of the `endpoint:<id>` queues and emits one event per queue with jobs: how long the oldest has been runnable (`seconds`) and how many are waiting (`available`). Empty queues and other queues (such as `maintenance`) emit nothing. A job's `scheduled_at` is when it became runnable (its insertion or the end of a snooze), so the lag is time spent waiting for a free slot, not backoff. A failing query is logged and the next tick tries again.

**Metrics** (`CourierWeb.Telemetry.metrics/0`). Every event has at least one metric, kept in memory by LiveDashboard:

| Metric | Kind | Tags |
|---|---|---|
| `courier.event.ingested.count` | counter | `type` |
| `courier.event.ingested.deliveries` | sum | |
| `courier.attempt.stop.duration` | summary (ms) | `outcome`, `status_class` |
| `courier.attempt.stop.duration` | counter (attempts) | `outcome` |
| `courier.attempt.stop.since_created_ms` | summary (ms), attempt 1 only: time to first attempt | `number` |
| `courier.attempt.exception.duration` | counter | |
| `courier.delivery.succeeded.attempts` | counter | |
| `courier.delivery.succeeded.total_ms` | summary (ms) | |
| `courier.delivery.failed.attempts` | counter | `reason` |
| `courier.delivery.retry_scheduled.delay_seconds` | counter and summary (s) | |
| `courier.endpoint.degraded.consecutive_failures` | counter | |
| `courier.endpoint.recovered.count` | counter | |
| `courier.queue.lag.seconds`, `courier.queue.lag.available` | last value | `queue` |

The generated Phoenix, Ecto and VM metrics stay. Exporting metrics to Prometheus or another backend and alerting are not part of v1.

**Admin dashboard.** LiveDashboard is at `/admin/dashboard` in every environment, behind HTTP Basic auth (`CourierWeb.Plugs.AdminAuth`): the password is the admin token and the user name is ignored. The password is compared in constant time.

| Situation | Response |
|---|---|
| Correct token as password | the dashboard |
| No credentials or wrong password | `401` with a `www-authenticate: Basic` challenge |
| No admin token configured (unset or empty) | `404`, so the route is hidden |

The token is `config :courier, :admin_token`, read from `COURIER_ADMIN_TOKEN` in `config/runtime.exs`. Development and test use fixed, non-secret tokens written in their config files; production has no default, so the dashboard answers `404` until the variable is set.

```sh
# development: any user name, the fixed dev token as password
open http://localhost:4000/admin/dashboard   # password: courier-dev-admin-token-not-a-secret
curl -s -o /dev/null -w "%{http_code}\n" -u admin:courier-dev-admin-token-not-a-secret \
  http://localhost:4000/admin/dashboard     # 302, to the dashboard's home page

# production: a long random token, served over HTTPS only
export COURIER_ADMIN_TOKEN="$(openssl rand -base64 32)"
```

The courier metrics are on the dashboard's "Metrics" page, grouped under `courier`.

## Security notes

- API keys are random tokens stored as SHA-256 hashes; the plaintext is shown once. Scopes: `ingest`, `read`, `write`.
- Endpoint secrets are encrypted at rest (AES-256-GCM via Cloak) because they must be readable to sign; the encryption key comes from `COURIER_ENCRYPTION_KEY`.
- `cloak` 1.1.4 and `cloak_ecto` 1.3.0 have open advisories: CVE-2026-95105 (the AES-CTR cipher is unauthenticated) and CVE-2026-94206 (the PBKDF2 field ignores the iteration count). They do not affect courier, which uses only `Cloak.Ciphers.AES.GCM` and `Cloak.Ecto.Binary`. Rule: never use Cloak's AES-CTR cipher or its PBKDF2 fields, and upgrade both packages when fixed versions are released.
- URL validation runs at creation **and** before every request (after DNS resolution), with a dev/demo-only host allowlist.
- DNS rebinding is not fully closed in v1: the URL policy resolves the host, then the HTTP client resolves it again to connect, so a host with a very short TTL could answer a public address to the check and a private one to the connection. Accepted for v1; the later hardening is to connect to the address the policy checked, keeping the original host for TLS SNI and the `host` header.
- Secrets, full signatures and `Authorization` headers are never logged or stored.
- Any repo call that writes a secret column passes `log: false`: Ecto logs query parameters at `debug` before Cloak encrypts them, so the plaintext would otherwise reach the logs.
- MCP tool results mark payloads and response bodies as untrusted data; `resend_delivery` needs `write` scope.
- The admin token (`COURIER_ADMIN_TOKEN`) opens LiveDashboard, which shows system internals: use a long random value and serve it only over HTTPS, because HTTP Basic auth sends it with every request. It is compared in constant time and never logged; without it the dashboard answers `404`. Telemetry metadata carries ids only, so the dashboard never shows payloads or secrets.
