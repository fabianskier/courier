defmodule Courier.Delivery.ObanQueueControl do
  @moduledoc "`Courier.Delivery.QueueControl` backed by Oban's runtime queue API."

  @behaviour Courier.Delivery.QueueControl

  @impl true
  def start(queue, opts) do
    limit = Keyword.fetch!(opts, :limit)
    local_only = Keyword.get(opts, :local_only, false)
    :ok = Oban.start_queue(queue: queue, limit: limit, local_only: local_only)
  end

  @impl true
  def scale(queue, limit), do: :ok = Oban.scale_queue(queue: queue, limit: limit)

  @impl true
  def stop(queue), do: :ok = Oban.stop_queue(queue: queue)
end
