# Proposal

## Why

Events, deliveries and attempts are kept forever, so the database grows without bound and old idempotency keys can never be reused. FR-37 to FR-39 ask for a daily job that prunes old, finished events; the retention ADR decides how, including the one controlled exception to append-only attempts.

## What Changes

- **Retention period**: `COURIER_RETENTION_DAYS` (default 30, minimum 2, longer than the 24 h retry window); an invalid value fails at boot with a clear message.
- **Pruning**: `Courier.Retention.prune/1` deletes an event with its deliveries and their attempts when every delivery is terminal and the event's last activity (its insertion or the latest delivery completion) is older than the period. It runs in batches of 1,000 events, each in one transaction that sets `courier.retention = on` so the attempts trigger allows the deletes.
- **Daily job**: an Oban cron worker in the `maintenance` queue runs the pruning once a day and reports the rows deleted per table (telemetry event and one `info` log line); LiveDashboard gets a metric for it.
- **Idempotency keys**: once an event is pruned, a repeat with its key creates a new event (FR-39); the README says so.
- **Not in this change**: archiving data before deleting it, per-merchant periods, pruning API keys, and a dashboard notice for pruned data (lists refresh on their next fetch).

## Capabilities

### New Capabilities
- `data-retention`: the retention period, which events are pruned, how deletion respects append-only attempts, the daily job and its report, and idempotency keys after pruning.

### Modified Capabilities
None. The attempts trigger and its `courier.retention` exception are already in `webhook-delivery` ("Attempts are append-only").

## Impact

- New `lib/courier/retention.ex` and `lib/courier/retention/worker.ex`; a cron entry in `config/config.exs`; `COURIER_RETENTION_DAYS` in `config/runtime.exs` (and a test default); a telemetry event in `Courier.Telemetry` and a metric in `CourierWeb.Telemetry`.
- No schema changes: the trigger exception exists since `add-webhook-delivery`.
- Existing tests are not modified.
