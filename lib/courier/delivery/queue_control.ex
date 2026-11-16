defmodule Courier.Delivery.QueueControl do
  @moduledoc """
  How `Courier.Delivery.QueueManager` starts, scales and stops queues. The
  implementation comes from the `:queue_control` application setting
  (default `Courier.Delivery.ObanQueueControl`), so tests can replace Oban,
  which runs no queues with `testing: :manual`.
  """

  @doc "Starts `queue` with `limit:`; `local_only: true` starts it on this node only."
  @callback start(queue :: String.t(), opts :: [limit: pos_integer(), local_only: boolean()]) ::
              :ok
  @doc "Changes the concurrency limit of a running `queue` on every node."
  @callback scale(queue :: String.t(), limit :: pos_integer()) :: :ok
  @doc "Stops `queue` on every node."
  @callback stop(queue :: String.t()) :: :ok

  @doc "Returns the configured implementation."
  @spec impl() :: module()
  def impl, do: Application.get_env(:courier, :queue_control, Courier.Delivery.ObanQueueControl)
end
