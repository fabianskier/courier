defmodule Courier.Retention.Worker do
  @moduledoc """
  Runs `Courier.Retention.prune/2` once a day in the `maintenance` queue.

  `Oban.Plugins.Cron` schedules it at 03:30 UTC. The period comes from
  `config :courier, :retention_days` (`COURIER_RETENTION_DAYS`, default 30).
  Every run reports the rows deleted per table, also when nothing was
  deleted: a `[:courier, :retention, :pruned]` telemetry event and one `info`
  log line. The pruning is idempotent, so a retried run only deletes what is
  still due.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  alias Courier.Retention

  @default_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    days = Application.get_env(:courier, :retention_days, @default_days)
    report = Retention.prune(days)

    Courier.Telemetry.emit_retention_pruned(report, days)

    Logger.info(
      "retention pruned events=#{report.events} deliveries=#{report.deliveries} " <>
        "attempts=#{report.attempts} days=#{days}"
    )

    :ok
  end
end
