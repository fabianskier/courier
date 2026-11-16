# demo-receiver Specification

## Purpose

A local webhook receiver for demos and end-to-end checks: it verifies courier's Standard Webhooks signatures independently and fails on purpose by path, so retries, dead letters, resend and per-endpoint isolation can be shown with real requests.

## Requirements

### Requirement: Behaviour by path
The receiver SHALL answer `POST /hooks/<name>/<behaviour>` according to the behaviour: `ok` answers `200`, `fail` answers `500`, `rate-limit` answers `429` with a `Retry-After` header of 30 seconds, `bad-request` answers `400`, and `timeout` answers `200` only after a configured delay longer than courier's request deadline. An unknown behaviour or path MUST answer `404`.

#### Scenario: Each behaviour answers as named
- **WHEN** a request with a valid signature is posted to each of `/hooks/shop/ok`, `/fail`, `/rate-limit` and `/bad-request`
- **THEN** the responses are `200`, `500`, `429` with `retry-after: 30`, and `400`

#### Scenario: Timeout answers late
- **WHEN** a request is posted to `/hooks/shop/timeout` with the delay configured to 200 ms
- **THEN** the response is `200` and arrives no sooner than 200 ms after the request

#### Scenario: Unknown behaviour
- **WHEN** a request is posted to `/hooks/shop/explode`
- **THEN** the response is `404`

### Requirement: Secret registration
The receiver SHALL accept `PUT /_secrets/<name>` with a JSON body `{"secret": "whsec_..."}` and use that secret, kept in memory only, to verify requests to `/hooks/<name>/...`. Registering again replaces the secret. A body without a `whsec_` secret whose remainder is valid base64 MUST answer `422` and change nothing. Names are 1 to 64 characters of lowercase letters, digits and `-`.

#### Scenario: Secret registered
- **WHEN** a secret is registered for `shop`
- **THEN** the response is `204` and later requests to `/hooks/shop/ok` are verified with it

#### Scenario: Invalid secret rejected
- **WHEN** `PUT /_secrets/shop` is sent with `{"secret": "not-a-secret"}`
- **THEN** the response is `422` and the previously registered secret for `shop`, if any, still applies

### Requirement: Signature verification
For a name with a registered secret, the receiver SHALL accept a request only when its `webhook-timestamp` is within 5 minutes of the receiver's clock and one of the `v1,` entries in `webhook-signature` equals the base64 HMAC-SHA256 of `<webhook-id>.<webhook-timestamp>.<raw body>` with the secret's decoded key, compared in constant time. Otherwise it MUST answer `401` without applying the behaviour.

#### Scenario: Valid signature accepted
- **WHEN** courier's delivery worker sends a delivery to an endpoint at `/hooks/shop/ok` on a running receiver that has the endpoint's secret registered
- **THEN** the receiver answers `200` and the attempt is stored as succeeded

#### Scenario: Wrong signature rejected
- **WHEN** a request to `/hooks/shop/fail` carries a signature made with another secret
- **THEN** the response is `401`, not `500`

#### Scenario: Stale timestamp rejected
- **WHEN** a correctly signed request has a `webhook-timestamp` 10 minutes in the past
- **THEN** the response is `401`

#### Scenario: Rotation overlap accepted
- **WHEN** `webhook-signature` holds two `v1,` entries and only the second matches the registered secret
- **THEN** the request is accepted

### Requirement: Unregistered names answered unchecked
For a name without a registered secret, the receiver SHALL apply the behaviour without verifying the signature and record that the request was unchecked, so the demo keeps working after the receiver restarts.

#### Scenario: Unchecked request
- **WHEN** an unsigned request is posted to `/hooks/other/ok` and no secret is registered for `other`
- **THEN** the response is `200` and the receiver's log line says `signature=unchecked`

### Requirement: Receiver logging
The receiver SHALL log one line per webhook request with the name, behaviour, signature result (`valid`, `invalid` or `unchecked`), `webhook-id` and `courier-delivery-id`. It MUST NOT log secrets, signatures, request bodies or the registration body.

#### Scenario: Log without secrets
- **WHEN** a secret is registered and a signed request is received
- **THEN** the captured log contains the webhook id and `signature=valid` and does not contain the secret, the signature or the request body
