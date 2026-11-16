defmodule Courier.Delivery.TestQueueControl do
  @moduledoc """
  `Courier.Delivery.QueueControl` for tests (Oban runs no queues with
  `testing: :manual`). It does nothing unless a test process called
  `register/0`; then every call is sent to that process as
  `{:queue_control, action, queue, arg}`.

  Registration uses a process name, so only one test can listen at a time:
  tests that register must be `async: false`.
  """

  @behaviour Courier.Delivery.QueueControl

  @doc "Makes the calling process receive every queue control call until it exits."
  def register, do: Process.register(self(), __MODULE__)

  @impl true
  def start(queue, opts), do: notify(:start, queue, opts)

  @impl true
  def scale(queue, limit), do: notify(:scale, queue, limit)

  @impl true
  def stop(queue), do: notify(:stop, queue, nil)

  defp notify(action, queue, arg) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> send(pid, {:queue_control, action, queue, arg})
    end

    :ok
  end
end
