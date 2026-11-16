# Design

## Context

`Courier.Delivery.record_attempt/3` locks the delivery, inserts the attempt and applies a transition (`{:succeeded, now}`, `{:failed, now}` or `{:retry_at, at}`) in one transaction. Queues are per endpoint (`QueueManager`); disabling an endpoint stops its queue but leaves its jobs `available`. Oban runs with `Pruner` and `Lifeline`, no static queues, `testing: :manual` in tests. ADR "Oban with one queue per endpoint …" asks for a test that a slow endpoint does not delay another endpoint's deliveries.

## Goals / Non-Goals

**Goals:** health counted exactly once per attempt, atomically with it; a degraded event emitted once per transition; every pending delivery eventually terminal.

**Non-Goals:** pausing or disabling degraded endpoints; metrics (step 6); per-endpoint thresholds.

## Decisions

### Columns

Migration `add_health_to_endpoints`: `consecutive_failures` integer, not null, default 0; `degraded_at` utc_datetime_usec, null. Index on `degraded_at` where not null. The schema reads both; no changeset casts them.

### Counting in `record_attempt/3`

After inserting the attempt, in the same transaction, lock the endpoint row (`SELECT ... FOR UPDATE`), compute the new values and update it:

- success (`{:succeeded, _}`): `consecutive_failures = 0`, `degraded_at = nil`; the health change is `:recovered` if `degraded_at` was set.
- failure (`{:failed, _}` or `{:retry_at, _}`): `consecutive_failures + 1`; when `degraded_at` was nil and the new count is at least the threshold, `degraded_at = now` and the health change is `:degraded`.

Lock order is always delivery, then endpoint, so concurrent attempts of one endpoint serialize briefly on the endpoint row without deadlocks. `fail_without_attempt/2` and stale results change nothing.

`record_attempt/3` returns the health change (`:degraded`, `:recovered` or `nil`) with its result; after the transaction commits, `Courier.Delivery` emits `:telemetry.execute([:courier, :endpoint, :degraded], %{consecutive_failures: n}, %{endpoint_id: id, merchant_id: mid})` or `[:courier, :endpoint, :recovered]` with `%{}` measurements. Emitting after commit avoids events for rolled-back changes.

Threshold: `Application.get_env(:courier, :degraded_threshold, 20)`, validated as a positive integer when read.

### API

`EndpointJSON` adds `consecutive_failures`, `degraded` (`degraded_at != nil`) and `degraded_at`. `Endpoints.list_endpoints/1` accepts `degraded: true | false | nil`; the controller maps `"true"`/`"false"` and ignores other values.

### Window sweeper

`Courier.Delivery.WindowSweeper` (`use Oban.Worker, queue: :maintenance, max_attempts: 3`), scheduled by `Oban.Plugins.Cron` every 5 minutes (`"*/5 * * * *"`); config gets `queues: [maintenance: 1]`. Each run selects up to 500 `pending` deliveries with `window_ends_at <= now` (oldest first), calls `fail_without_attempt/2` on each, and cancels their delivery jobs with `Oban.cancel_all_jobs/1` on `args->>'delivery_id'` in the batch. If the batch was full, it inserts itself again to continue. In tests it is called with `perform_job/2`.

### Isolation test

A test-only Oban instance (`name: Courier.IsolationOban`, `testing: :disabled`, `notifier: Oban.Notifiers.Isolated`, `plugins: [Oban.Plugins.Stager]` or the shortest stage interval that works, `queues: []`) started with `start_supervised!`, the SQL sandbox in shared mode, two Bandit servers on loopback (one sleeps 3 s before answering, one answers `200` at once), the URL policy allowlist and the client config overridden for the test's duration (`async: false`, restored on exit). Two endpoints with `max_concurrency: 2`; queues started with `Oban.start_queue(Courier.IsolationOban, ...)`. Insert 6 jobs for the slow endpoint, then 1 for the fast one; assert the fast delivery is `succeeded` within 2 s of its insertion (poll the row) while the slow endpoint still has jobs executing. If real queues cannot run reliably under the sandbox, the task reports it instead of weakening the assertion.

## Risks / Trade-offs

- [Endpoint row lock adds contention per endpoint] → One short `UPDATE` per attempt, limited by `max_concurrency` (≤ 50).
- [The sweeper fails deliveries of an endpoint that is re-enabled after their window] → Correct per the window rule; resend (step 5) is the way to deliver them.
- [Threshold is global] → Per-endpoint thresholds can come later if needed.

## Migration Plan

One additive migration; rollback drops the index and both columns.
