defmodule Courier.Delivery do
  @moduledoc """
  Reads deliveries and records the outcome of delivery attempts.

  A delivery's status only moves forward, from `pending` to `succeeded` or
  `failed`. Every write locks the delivery row (`FOR UPDATE`) inside a short
  transaction, never held during the HTTP request, and does nothing when the
  delivery is no longer `pending`, so a late or duplicate result is ignored.
  """

  import Ecto.Query, warn: false

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Endpoints.Endpoint
  alias Courier.Repo

  @default_degraded_threshold 20

  @type transition ::
          {:succeeded, DateTime.t()} | {:failed, DateTime.t()} | {:retry_at, DateTime.t()}

  @type health_change :: :degraded | :recovered | nil

  @doc """
  Returns `{:ok, delivery}` with its attempts preloaded in `number` order, or
  `{:error, :not_found}` for an unknown or malformed id.
  """
  @spec get_delivery(term()) :: {:ok, Delivery.t()} | {:error, :not_found}
  def get_delivery(id) do
    attempts = from a in Attempt, order_by: [asc: a.number]

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Delivery{} = delivery <- Repo.get(Delivery, uuid) do
      {:ok, Repo.preload(delivery, attempts: attempts)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Stores an attempt for a pending delivery and applies `transition` in one
  transaction.

  `attempt_attrs` (atom keys, set by the system) holds the attempt fields
  except `delivery_id` and `number`; the number is `attempt_count + 1`.

    * `{:succeeded, now}` / `{:failed, now}` set the status and `completed_at`
      and clear `next_attempt_at`.
    * `{:retry_at, at}` keeps the delivery `pending` and sets `next_attempt_at`.

  In the same transaction the endpoint's health is updated (the endpoint row
  is locked after the delivery row): a success resets
  `consecutive_failures` and clears `degraded_at`; a failure (`:failed` or
  `:retry_at`) adds one and sets `degraded_at` when the count reaches the
  threshold (`config :courier, :degraded_threshold`, default
  #{@default_degraded_threshold}). After commit, the telemetry event
  `[:courier, :endpoint, :degraded]` or `[:courier, :endpoint, :recovered]`
  is emitted for the health change.

  Returns `{:ok, %{delivery: delivery, attempt: attempt, health: health}}`
  where `health` is `:degraded`, `:recovered` or `nil`, `{:ok, :stale}`
  when the delivery is not `pending` (nothing is stored), or
  `{:error, :not_found}` / `{:error, changeset}`.
  """
  @spec record_attempt(Ecto.UUID.t(), map(), transition()) ::
          {:ok, %{delivery: Delivery.t(), attempt: Attempt.t(), health: health_change()}}
          | {:ok, :stale}
          | {:error, :not_found | Ecto.Changeset.t()}
  def record_attempt(delivery_id, attempt_attrs, transition) do
    Repo.transact(fn ->
      with {:ok, delivery} <- lock_pending(delivery_id),
           {:ok, attempt} <- insert_attempt(delivery, attempt_attrs),
           {:ok, delivery} <- apply_transition(delivery, transition, attempt.number),
           {:ok, endpoint, health} <- update_health(delivery.endpoint_id, transition) do
        {:ok, %{delivery: delivery, attempt: attempt, health: health, endpoint: endpoint}}
      end
    end)
    |> stale_as_ok()
    |> emit_health()
  end

  @doc """
  Returns the number of consecutive failed attempts at which an endpoint is
  marked degraded (`config :courier, :degraded_threshold`, a positive
  integer, default #{@default_degraded_threshold}).
  """
  @spec degraded_threshold() :: pos_integer()
  def degraded_threshold do
    case Application.get_env(:courier, :degraded_threshold, @default_degraded_threshold) do
      threshold when is_integer(threshold) and threshold > 0 ->
        threshold

      other ->
        raise ArgumentError,
              "config :courier, :degraded_threshold must be a positive integer, got: " <>
                inspect(other)
    end
  end

  @doc """
  Marks a pending delivery `failed` without storing an attempt, for when its
  retry window ended before another attempt could be made.

  Returns `{:ok, delivery}`, `{:ok, :stale}` when it is no longer `pending`,
  or `{:error, :not_found}`.
  """
  @spec fail_without_attempt(Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Delivery.t()} | {:ok, :stale} | {:error, :not_found | Ecto.Changeset.t()}
  def fail_without_attempt(delivery_id, now) do
    Repo.transact(fn ->
      with {:ok, delivery} <- lock_pending(delivery_id) do
        apply_transition(delivery, {:failed, now}, delivery.attempt_count)
      end
    end)
    |> stale_as_ok()
  end

  defp lock_pending(delivery_id) do
    query = from d in Delivery, where: d.id == ^delivery_id, lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> {:error, :not_found}
      %Delivery{status: "pending"} = delivery -> {:ok, delivery}
      %Delivery{} -> {:error, :stale}
    end
  end

  defp insert_attempt(%Delivery{} = delivery, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.merge(%{delivery_id: delivery.id, number: delivery.attempt_count + 1})

    %Attempt{}
    |> Attempt.create_changeset(attrs)
    |> Repo.insert()
  end

  defp apply_transition(%Delivery{} = delivery, transition, attempt_count) do
    delivery
    |> Ecto.Changeset.change([{:attempt_count, attempt_count} | transition_changes(transition)])
    |> Repo.update()
  end

  defp transition_changes({status, %DateTime{} = now}) when status in [:succeeded, :failed] do
    [status: Atom.to_string(status), completed_at: now, next_attempt_at: nil]
  end

  defp transition_changes({:retry_at, %DateTime{} = at}), do: [next_attempt_at: at]

  defp update_health(endpoint_id, transition) do
    endpoint = Repo.one!(from e in Endpoint, where: e.id == ^endpoint_id, lock: "FOR UPDATE")
    {changes, health} = health_changes(endpoint, transition)

    with {:ok, endpoint} <- endpoint |> Ecto.Changeset.change(changes) |> Repo.update() do
      {:ok, endpoint, health}
    end
  end

  defp health_changes(%Endpoint{degraded_at: degraded_at}, {:succeeded, _now}) do
    health = if degraded_at, do: :recovered
    {[consecutive_failures: 0, degraded_at: nil], health}
  end

  defp health_changes(%Endpoint{} = endpoint, {status, %DateTime{} = now})
       when status in [:failed, :retry_at] do
    count = endpoint.consecutive_failures + 1

    if is_nil(endpoint.degraded_at) and count >= degraded_threshold() do
      # `{:retry_at, at}` carries the next attempt time, not the current one.
      {[consecutive_failures: count, degraded_at: degraded_time(status, now)], :degraded}
    else
      {[consecutive_failures: count], nil}
    end
  end

  defp degraded_time(:failed, now), do: now
  defp degraded_time(:retry_at, _at), do: DateTime.utc_now()

  # Runs after the transaction, so a rolled-back change emits nothing.
  defp emit_health({:ok, %{endpoint: endpoint, health: health} = recorded}) do
    metadata = %{endpoint_id: endpoint.id, merchant_id: endpoint.merchant_id}

    case health do
      :degraded ->
        :telemetry.execute(
          [:courier, :endpoint, :degraded],
          %{consecutive_failures: endpoint.consecutive_failures},
          metadata
        )

      :recovered ->
        :telemetry.execute([:courier, :endpoint, :recovered], %{}, metadata)

      nil ->
        :ok
    end

    {:ok, Map.delete(recorded, :endpoint)}
  end

  defp emit_health(result), do: result

  defp stale_as_ok({:error, :stale}), do: {:ok, :stale}
  defp stale_as_ok(result), do: result
end
