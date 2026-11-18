# Design

## Context

See proposal.md and the retention ADR in `docs/decisions.md`. What exists:

- `attempts_append_only` trigger: `UPDATE` always fails; `DELETE` fails unless `current_setting('courier.retention', true) = 'on'`.
- Foreign keys are all `ON DELETE RESTRICT`: `attempts.delivery_id`, `deliveries.event_id`, `deliveries.endpoint_id` and `deliveries.resend_of_id` (a resend points at the delivery it resends, of the same event). Postgres checks `RESTRICT` per row, even when both rows are deleted in the same statement.
- Oban runs `Oban.Plugins.Cron` with the `Courier.Delivery.WindowSweeper` every 5 minutes in the static `maintenance` queue; `Oban.Plugins.Pruner` already prunes old jobs.
- `Courier.Telemetry` emits events after commit; `CourierWeb.Telemetry` lists metrics for LiveDashboard.
- Indexes: `events (inserted_at, id)`, `deliveries (event_id, endpoint_id)` unique, `deliveries (inserted_at, id)`, `attempts (delivery_id, number)` unique.

## Goals / Non-Goals

**Goals:** one plain-SQL path that is the only place allowed to delete attempts; short transactions; correct handling of resend links; a report every run.

**Non-Goals:** archiving, vacuum tuning, and pruning Oban jobs (the Pruner does that).

## Decisions

**Config.** `config/runtime.exs` parses `COURIER_RETENTION_DAYS` with `Integer.parse/1` (whole string), raising `"COURIER_RETENTION_DAYS must be a whole number of days, at least 2"` otherwise; unset means 30. It sets `config :courier, :retention_days`. The parsing lives in `Courier.Retention.parse_days/1` so the scenarios test it without booting.

**Selecting events.** One query picks up to 1,000 event ids per batch:

```sql
SELECT e.id FROM events e
LEFT JOIN deliveries d ON d.event_id = e.id
GROUP BY e.id
HAVING bool_and(d.status IS NULL OR d.status <> 'pending')
   AND greatest(e.inserted_at, max(d.completed_at)) < $cutoff
ORDER BY e.inserted_at
LIMIT 1000
```

(`greatest` ignores a null `max`.) `cutoff = now - days`.

**Deleting a batch.** In one `Repo.transaction`:
1. `SET LOCAL courier.retention = 'on'`;
2. delete the batch's attempts (`WHERE delivery_id IN (deliveries of the batch)`);
3. delete the batch's deliveries in rounds, each round removing those no other delivery points at through `resend_of_id`, until none are left (rounds are bounded by the longest resend chain), then its events;
4. set `courier.retention` back to `off` before the transaction ends.
The counts come from each `delete_all`. Batches repeat until a batch is smaller than 1,000. Each batch re-selects, so events that changed meanwhile are re-checked.
*Alternatives:* clearing `resend_of_id` first (rejected while building: a resend would become a second original and break the unique index on originals), or changing the foreign key to `ON DELETE SET NULL` or a deferrable constraint (a migration for a job-only concern).

**Job.** `Courier.Retention.Worker` (`use Oban.Worker, queue: :maintenance, max_attempts: 3`) calls `Courier.Retention.prune(days)` and returns `:ok`. Cron entry `{"30 3 * * *", Courier.Retention.Worker}` (daily, 03:30 UTC). As built, the entry lives in its own plugin, `{Courier.Retention.Cron, crontab: [...]}`, a thin module that delegates to `Oban.Cron`: Oban rejects a plugin module listed twice, and the `Oban.Plugins.Cron` crontab is pinned to the sweeper by an existing test. After the run: `:telemetry.execute([:courier, :retention, :pruned], %{events: e, deliveries: d, attempts: a}, %{days: days})` and `Logger.info("retention pruned events=… deliveries=… attempts=… days=…")`. `CourierWeb.Telemetry` adds `sum("courier.retention.pruned.events")` (and deliveries, attempts).

**Return value.** `prune(days, opts \\ [])` returns `%{events: n, deliveries: n, attempts: n, batches: n}`; `opts[:batch_size]` defaults to 1,000 and `opts[:now]` to `DateTime.utc_now()`, so tests control both.

**Tests.** `test/courier/retention_test.exs` builds old data with the existing fixtures and then moves `inserted_at`/`completed_at` back with `Repo.update_all` (events and deliveries allow updates); the 2,500-event batch scenario inserts rows with `Repo.insert_all` and asserts `batches: 3` and empty tables. The trigger scenario runs a plain `Repo.delete_all(Attempt)` and expects a `Postgrex.Error`. `test/courier/retention_worker_test.exs` covers the report (telemetry handler and `capture_log`) and the cron entry, read from the Oban config.

## Risks / Trade-offs

- [The selection query scans events with a `GROUP BY`] → fine at demo scale and run once a day; an index on `deliveries (event_id, status)` can come with the load test (step 14) if needed.
- [A long first run after enabling retention on a big database] → batches keep each transaction short; the job may take several batches.

## Migration Plan

No schema changes. Deploying enables the daily job with 30 days unless `COURIER_RETENTION_DAYS` says otherwise. Rollback: revert the change; already pruned data stays deleted.
