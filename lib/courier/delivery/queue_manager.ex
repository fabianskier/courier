defmodule Courier.Delivery.QueueManager do
  @moduledoc """
  Keeps one Oban queue per enabled endpoint (see `Courier.Delivery.Queues`).

  Started after Oban: on init it starts the queues of all enabled endpoints on
  this node. `sync/1`, called after an endpoint is created or updated, starts
  the endpoint's queue, scales it to `max_concurrency` or stops it when the
  endpoint is disabled, on every node.

  The manager remembers which queues it started and their limits, so `sync/1`
  only sends Oban a signal when something changed. That state is per node,
  which matches the single-node scope of v1 (see `docs/decisions.md`).
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Courier.Delivery.QueueControl
  alias Courier.Delivery.Queues
  alias Courier.Endpoints.Endpoint
  alias Courier.Repo

  @doc """
  Starts the manager. Options: `:name` (default `#{inspect(__MODULE__)}`) and
  `:queue_control` (default from `Courier.Delivery.QueueControl.impl/0`).
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Brings the endpoint's queue in line with its `enabled` flag and `max_concurrency`."
  @spec sync(Endpoint.t(), GenServer.server()) :: :ok
  def sync(%Endpoint{} = endpoint, server \\ __MODULE__) do
    GenServer.call(server, {:sync, endpoint})
  end

  @impl true
  def init(opts) do
    control = Keyword.get_lazy(opts, :queue_control, &QueueControl.impl/0)

    queues =
      Repo.all(from e in Endpoint, where: e.enabled, select: {e.id, e.max_concurrency})
      |> Map.new(fn {id, limit} ->
        queue = Queues.name(id)
        :ok = control.start(queue, limit: limit, local_only: true)
        {queue, limit}
      end)

    {:ok, %{control: control, queues: queues}}
  end

  @impl true
  def handle_call({:sync, %Endpoint{} = endpoint}, _from, state) do
    queue = Queues.name(endpoint.id)
    queues = apply_change(state.control, state.queues, queue, endpoint)
    {:reply, :ok, %{state | queues: queues}}
  end

  defp apply_change(control, queues, queue, %Endpoint{enabled: true, max_concurrency: limit}) do
    case Map.fetch(queues, queue) do
      {:ok, ^limit} ->
        queues

      {:ok, _other} ->
        :ok = control.scale(queue, limit)
        Map.put(queues, queue, limit)

      :error ->
        :ok = control.start(queue, limit: limit, local_only: false)
        Map.put(queues, queue, limit)
    end
  end

  defp apply_change(control, queues, queue, %Endpoint{enabled: false}) do
    if Map.has_key?(queues, queue) do
      :ok = control.stop(queue)
      Map.delete(queues, queue)
    else
      queues
    end
  end
end
