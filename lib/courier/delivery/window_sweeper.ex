defmodule Courier.Delivery.WindowSweeper do
  @moduledoc """
  Fails pending deliveries whose retry window has ended.

  A delivery normally ends in its own job, but the job of a disabled endpoint
  never runs because its queue is stopped. `Oban.Plugins.Cron` runs this
  worker every 5 minutes in the `maintenance` queue so every pending delivery
  eventually becomes terminal.

  Each run takes up to 500 pending deliveries with `window_ends_at <= now`
  (oldest first), cancels their delivery jobs and marks each one `failed`
  without an attempt (`Courier.Delivery.fail_without_attempt/2`). Jobs are
  cancelled first: if the run crashes in between, the deliveries are still
  `pending` and the next run picks them up. When the batch was full the
  worker inserts itself again to continue.

  The optional `"batch_size"` job argument overrides the batch size.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  import Ecto.Query, warn: false

  alias Courier.Delivery
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Repo

  @default_batch_size 500
  @delivery_worker inspect(Courier.Delivery.Worker)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    now = DateTime.utc_now()
    batch_size = batch_size(args)
    ids = expired_ids(now, batch_size)

    with :ok <- cancel_jobs(ids),
         :ok <- fail_all(ids, now) do
      continue(ids, batch_size, args)
    end
  end

  defp batch_size(%{"batch_size" => size}) when is_integer(size) and size > 0, do: size
  defp batch_size(_args), do: @default_batch_size

  defp expired_ids(now, batch_size) do
    Repo.all(
      from d in DeliveryRecord,
        where: d.status == "pending" and d.window_ends_at <= ^now,
        order_by: [asc: d.window_ends_at, asc: d.id],
        limit: ^batch_size,
        select: d.id
    )
  end

  defp cancel_jobs([]), do: :ok

  defp cancel_jobs(ids) do
    query =
      from j in Oban.Job,
        where: j.worker == ^@delivery_worker,
        where: fragment("?->>'delivery_id'", j.args) in ^ids

    with {:ok, _count} <- Oban.cancel_all_jobs(query), do: :ok
  end

  # A delivery that finished or disappeared since it was selected is skipped.
  defp fail_all(ids, now) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case Delivery.fail_without_attempt(id, now) do
        {:ok, _delivery_or_stale} -> {:cont, :ok}
        {:error, :not_found} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp continue(ids, batch_size, args) when length(ids) == batch_size do
    with {:ok, _job} <- args |> new() |> Oban.insert(), do: :ok
  end

  defp continue(_ids, _batch_size, _args), do: :ok
end
