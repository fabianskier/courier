# Proposal

## Why

`Courier.Application` starts Oban (and the queue manager) before the `Courier.Finch` pool and `Courier.Delivery.TaskSupervisor`. A delivery job that runs right after boot can find neither and crash; Oban retries it as an error, so nothing is lost, but the attempt is wasted and the error is misleading. On shutdown the order is also wrong: children stop in reverse order, so Finch and the task supervisor stop while Oban may still be finishing jobs.

## What Changes

- Start `Courier.Finch` and `Courier.Delivery.TaskSupervisor` before Oban, so they are up before any job runs and stop only after Oban has stopped.
- A test pins the order of the children that delivery depends on.
- Not in this change: anything else in the supervision tree.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `webhook-delivery`: new requirement "Delivery dependencies outlive delivery jobs".

## Impact

- `lib/courier/application.ex` only, plus a new test file. No new dependencies; existing tests are not modified.
