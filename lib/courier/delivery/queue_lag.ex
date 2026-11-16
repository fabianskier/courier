defmodule Courier.Delivery.QueueLag do
  @moduledoc """
  Measures how far behind the endpoint queues are.

  `measure/0` is a periodic measurement of `CourierWeb.Telemetry`'s poller.
  For each `endpoint:<id>` queue with jobs in state `available` it emits
  `[:courier, :queue, :lag]` with how long the oldest of them has been
  runnable (`seconds`) and how many there are (`available`). Queues without
  available jobs emit nothing.

  A job's `scheduled_at` is when it became runnable (its insertion, or the end
  of a snooze), so the lag is time spent waiting for a worker, not backoff.
  """

  import Ecto.Query

  alias Courier.Repo
  alias Courier.Telemetry

  require Logger

  @doc """
  Emits one `[:courier, :queue, :lag]` event per endpoint queue with available
  jobs.

  Always returns `:ok`: the poller drops a measurement that raises, so a
  failing query is logged and the next tick tries again.
  """
  @spec measure() :: :ok
  def measure do
    Enum.each(lags(), fn {queue, available, seconds} ->
      Telemetry.emit_queue_lag(queue, seconds, available)
    end)
  rescue
    exception ->
      Logger.warning("queue lag measurement failed: #{inspect(exception.__struct__)}")
      :ok
  end

  # `clock_timestamp()` rather than `now()`: `now()` is the start of the
  # current transaction, which is not the present when the caller is in one.
  defp lags do
    Repo.all(
      from job in Oban.Job,
        where: job.state == "available" and like(job.queue, "endpoint:%"),
        group_by: job.queue,
        select: {
          job.queue,
          count(),
          fragment(
            "GREATEST(EXTRACT(EPOCH FROM max(clock_timestamp() - ?)), 0)::float8",
            job.scheduled_at
          )
        }
    )
  end
end
