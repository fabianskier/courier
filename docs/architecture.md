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
- **Concurrency and isolation.** Each enabled endpoint has its own Oban queue (`endpoint:<id>`) with its own limit, so deliveries run concurrently across endpoints and a slow endpoint only uses its own slots. `QueueManager` keeps the running queues in sync with the endpoints table (at boot and on every endpoint change).
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
        alt failures >= N
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
        string triggered_by "system | api_key name"
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

**Pagination** (`Courier.Pagination`). List endpoints take `limit` (default 50, 1 to 100) and an opaque `cursor`, and answer `{"data": [...], "next_cursor": "..."}`, with `next_cursor` `null` on the last page. Pagination is keyset on `(inserted_at, id)` ascending, so items are oldest first and pages do not repeat or skip rows when new ones are inserted. The cursor is URL-safe base64 of the last item's timestamp and id; an invalid `limit` or a cursor the system did not issue returns `422 invalid`. `GET /api/v1/endpoints` also accepts `merchant_id`.

```sh
curl -s -X POST http://localhost:4000/api/v1/endpoints -H "Authorization: Bearer $COURIER_TOKEN" \
  -H "content-type: application/json" \
  -d '{"merchant_id": "<id>", "url": "https://hooks.example.com/courier", "event_types": ["payment.*"]}'
# {"data": {"id": "...", "enabled": true, "retry_window_seconds": 86400, ..., "secret": "whsec_..."}}
```

## Security notes

- API keys are random tokens stored as SHA-256 hashes; the plaintext is shown once. Scopes: `ingest`, `read`, `write`.
- Endpoint secrets are encrypted at rest (AES-256-GCM via Cloak) because they must be readable to sign; the encryption key comes from `COURIER_ENCRYPTION_KEY`.
- `cloak` 1.1.4 and `cloak_ecto` 1.3.0 have open advisories: CVE-2026-95105 (the AES-CTR cipher is unauthenticated) and CVE-2026-94206 (the PBKDF2 field ignores the iteration count). They do not affect courier, which uses only `Cloak.Ciphers.AES.GCM` and `Cloak.Ecto.Binary`. Rule: never use Cloak's AES-CTR cipher or its PBKDF2 fields, and upgrade both packages when fixed versions are released.
- URL validation runs at creation **and** before every request (after DNS resolution), with a dev/demo-only host allowlist.
- Secrets, full signatures and `Authorization` headers are never logged or stored.
- MCP tool results mark payloads and response bodies as untrusted data; `resend_delivery` needs `write` scope.
