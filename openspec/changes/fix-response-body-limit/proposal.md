# Proposal

## Why

`Courier.Delivery.Client` keeps only the first 4 KB of a response body, but Req reads the whole body into memory before it is truncated. A receiver that answers with a very large body, or one that sends its body a few bytes at a time, can make a delivery job use unbounded memory or stay busy for hours, taking a slot of its endpoint's queue and memory shared with every other endpoint. The endpoint is controlled by a merchant, so courier must bound what it accepts from it.

## What Changes

- The client streams the response body and stops reading after 4096 bytes, closing the connection; the stored body stays the first 4096 bytes.
- Each request gets a total deadline of 30 seconds, from connect to the end of reading (connect and per-read timeouts alone do not bound a body that trickles in). A request that exceeds it fails with error `timeout` and is retried like any timeout.
- `Client.post/4` accepts options that override the configured ones, so a test can reach a real local server instead of the `Req.Test` stub.
- Not in this change: limits on response headers (Mint already bounds them), DNS rebinding.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `webhook-delivery`: new requirement "Bounded response reading".

## Impact

- `lib/courier/delivery/client.ex` only; the worker keeps calling `post/3`.
- No new dependencies (tests use Bandit, already a dependency, as the local server).
- Existing tests are not modified.
