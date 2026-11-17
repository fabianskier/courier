defmodule Courier.Delivery do
  @moduledoc """
  Reads deliveries, records the outcome of delivery attempts and resends
  terminal deliveries as new linked deliveries.

  A delivery's status only moves forward, from `pending` to `succeeded` or
  `failed`. Every write locks the delivery row (`FOR UPDATE`) inside a short
  transaction, never held during the HTTP request, and does nothing when the
  delivery is no longer `pending`, so a late or duplicate result is ignored.
  """

  import Ecto.Query, warn: false

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Delivery.{Queues, Worker}
  alias Courier.Endpoints.Endpoint
  alias Courier.Pagination
  alias Courier.Repo
  alias Courier.Telemetry

  @default_degraded_threshold 20

  @type transition ::
          {:succeeded, DateTime.t()}
          | {:failed, DateTime.t()}
          | {:failed, DateTime.t(), Telemetry.failure_reason()}
          | {:retry_at, DateTime.t()}

  @type health_change :: :degraded | :recovered | nil

  @doc """
  Returns `{:ok, delivery}` with its attempts preloaded in `number` order and
  its direct resends preloaded oldest first, or `{:error, :not_found}` for an
  unknown or malformed id.
  """
  @spec get_delivery(term()) :: {:ok, Delivery.t()} | {:error, :not_found}
  def get_delivery(id) do
    attempts = from a in Attempt, order_by: [asc: a.number]
    resends = from d in Delivery, order_by: [asc: d.inserted_at, asc: d.id]

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Delivery{} = delivery <- Repo.get(Delivery, uuid) do
      {:ok, Repo.preload(delivery, attempts: attempts, resends: resends)}
    else
      _ -> {:error, :not_found}
    end
  end

  @default_list_limit 20

  @doc """
  Lists deliveries newest first (`inserted_at`, then `id`), without attempts.

  `opts` may hold the filters `:status`, `:endpoint_id` and `:event_id` (a nil
  or missing filter is not applied; an id that is not a UUID matches nothing),
  `:limit` (default #{@default_list_limit}) and `:cursor`, the `next_cursor`
  of a previous page.

  Returns `{:ok, %{items: deliveries, next_cursor: cursor_or_nil}}` or
  `{:error, :invalid_cursor}`.
  """
  @spec list_deliveries(%{
          optional(:status) => String.t() | nil,
          optional(:endpoint_id) => term(),
          optional(:event_id) => term(),
          optional(:limit) => pos_integer() | nil,
          optional(:cursor) => String.t() | nil
        }) :: {:ok, Pagination.page()} | {:error, :invalid_cursor}
  def list_deliveries(opts) when is_map(opts) do
    page_opts = %{
      limit: Map.get(opts, :limit) || @default_list_limit,
      cursor: Map.get(opts, :cursor),
      order: :desc
    }

    Delivery
    |> filter_status(Map.get(opts, :status))
    |> filter_id(:endpoint_id, Map.get(opts, :endpoint_id))
    |> filter_id(:event_id, Map.get(opts, :event_id))
    |> Pagination.paginate(page_opts)
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, status) when is_binary(status), do: where(query, status: ^status)
  defp filter_status(query, _status), do: where(query, false)

  defp filter_id(query, _field, nil), do: query

  defp filter_id(query, field, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> where(query, [d], field(d, ^field) == ^uuid)
      :error -> where(query, false)
    end
  end

  @doc """
  Returns the number of deliveries of an endpoint for each status, as
  `%{pending: n, succeeded: n, failed: n, skipped: n}`. Every count is zero
  for an unknown or malformed endpoint id.
  """
  @spec count_by_status(term()) :: %{
          pending: non_neg_integer(),
          succeeded: non_neg_integer(),
          failed: non_neg_integer(),
          skipped: non_neg_integer()
        }
  def count_by_status(endpoint_id) do
    counts =
      case Ecto.UUID.cast(endpoint_id) do
        {:ok, uuid} ->
          query =
            from d in Delivery,
              where: d.endpoint_id == ^uuid,
              group_by: d.status,
              select: {d.status, count(d.id)}

          query |> Repo.all() |> Map.new()

        :error ->
          %{}
      end

    %{
      pending: Map.get(counts, "pending", 0),
      succeeded: Map.get(counts, "succeeded", 0),
      failed: Map.get(counts, "failed", 0),
      skipped: Map.get(counts, "skipped", 0)
    }
  end

  @doc """
  Stores an attempt for a pending delivery and applies `transition` in one
  transaction.

  `attempt_attrs` (atom keys, set by the system) holds the attempt fields
  except `delivery_id` and `number`; the number is `attempt_count + 1`.

    * `{:succeeded, now}` / `{:failed, now}` set the status and `completed_at`
      and clear `next_attempt_at`. `{:failed, now, reason}` does the same and
      names why (`:non_retryable`, the default, or `:window_ended`).
    * `{:retry_at, at}` keeps the delivery `pending` and sets `next_attempt_at`.

  After commit, one delivery outcome event is emitted (see
  `Courier.Telemetry`): `[:courier, :delivery, :succeeded]`,
  `[:courier, :delivery, :failed]` or `[:courier, :delivery, :retry_scheduled]`.

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
    {transition, reason} = split_reason(transition)

    Repo.transact(fn ->
      with {:ok, delivery} <- lock_pending(delivery_id),
           {:ok, attempt} <- insert_attempt(delivery, attempt_attrs),
           {:ok, delivery} <- apply_transition(delivery, transition, attempt.number),
           {:ok, endpoint, health} <- update_health(delivery.endpoint_id, transition) do
        {:ok, %{delivery: delivery, attempt: attempt, health: health, endpoint: endpoint}}
      end
    end)
    |> stale_as_ok()
    |> emit_outcome(transition, reason)
    |> emit_health()
  end

  defp split_reason({:failed, %DateTime{} = now, reason})
       when reason in [:non_retryable, :window_ended],
       do: {{:failed, now}, reason}

  defp split_reason({:failed, %DateTime{}} = transition), do: {transition, :non_retryable}
  defp split_reason(transition), do: {transition, nil}

  # Runs after the transaction, so a rolled-back or stale result emits nothing.
  defp emit_outcome({:ok, %{delivery: delivery, attempt: attempt}} = result, transition, reason) do
    case transition do
      {:succeeded, _now} ->
        Telemetry.emit_delivery_succeeded(delivery)

      {:failed, _now} ->
        Telemetry.emit_delivery_failed(delivery, reason)

      {:retry_at, at} ->
        Telemetry.emit_delivery_retry_scheduled(delivery, delay_seconds(attempt, at))
    end

    result
  end

  defp emit_outcome(result, _transition, _reason), do: result

  # The delay counts from the end of the attempt, rounded to whole seconds.
  defp delay_seconds(%Attempt{started_at: started_at, duration_ms: duration_ms}, at) do
    finished_at = DateTime.add(started_at, duration_ms, :millisecond)
    max(round(DateTime.diff(at, finished_at, :millisecond) / 1000), 0)
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
  retry window ended before another attempt could be made. After commit it
  emits `[:courier, :delivery, :failed]` with reason `:window_ended`.

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
    |> emit_window_ended()
  end

  # Runs after the transaction; a stale result changed nothing and emits nothing.
  defp emit_window_ended({:ok, %Delivery{} = delivery} = result) do
    Telemetry.emit_delivery_failed(delivery, :window_ended)
    result
  end

  defp emit_window_ended(result), do: result

  @doc """
  Resends a terminal delivery (`succeeded`, `failed` or `skipped`) as a new
  `pending` delivery for the same event and endpoint, linked to it by
  `resend_of_id`, with `triggered_by` set to `actor` (a non-empty string,
  such as `"api_key:ops"`) and a retry window starting now. The new delivery
  and its job in the endpoint's queue are inserted in one transaction; the
  resent delivery and its attempts are not changed.

  The resent delivery's row is locked, so concurrent resends of it create at
  most one new delivery. A `skipped` delivery can be resent: the operator
  asks for it explicitly, so the endpoint's event filter does not apply.

  Returns `{:ok, new_delivery}`, or `{:error, reason}` where `reason` is:

    * `:not_found` for an unknown or malformed id;
    * `:delivery_in_progress` when the delivery is `pending`;
    * `:resend_in_progress` when it already has a `pending` resend;
    * `:endpoint_disabled` when its endpoint is disabled.
  """
  @spec resend(term(), String.t()) ::
          {:ok, Delivery.t()}
          | {:error,
             :not_found
             | :delivery_in_progress
             | :resend_in_progress
             | :endpoint_disabled
             | Ecto.Changeset.t()}
  def resend(delivery_id, actor) when is_binary(actor) and actor != "" do
    Repo.transact(fn ->
      with {:ok, delivery} <- lock_terminal(delivery_id),
           :ok <- check_no_pending_resend(delivery),
           {:ok, endpoint} <- enabled_endpoint(delivery.endpoint_id),
           {:ok, resend} <- insert_resend(delivery, endpoint, actor),
           {:ok, _job} <- insert_job(resend) do
        {:ok, resend}
      end
    end)
  end

  defp lock_terminal(delivery_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(delivery_id),
         query = from(d in Delivery, where: d.id == ^uuid, lock: "FOR UPDATE"),
         %Delivery{} = delivery <- Repo.one(query) do
      if delivery.status == "pending",
        do: {:error, :delivery_in_progress},
        else: {:ok, delivery}
    else
      _ -> {:error, :not_found}
    end
  end

  # Race-free: the caller holds the lock on `delivery`, which serializes
  # concurrent resends of it.
  defp check_no_pending_resend(%Delivery{id: id}) do
    pending = from d in Delivery, where: d.resend_of_id == ^id and d.status == "pending"

    if Repo.exists?(pending), do: {:error, :resend_in_progress}, else: :ok
  end

  defp enabled_endpoint(endpoint_id) do
    case Repo.get(Endpoint, endpoint_id) do
      %Endpoint{enabled: true} = endpoint -> {:ok, endpoint}
      _disabled_or_missing -> {:error, :endpoint_disabled}
    end
  end

  defp insert_resend(%Delivery{} = delivery, %Endpoint{} = endpoint, actor) do
    %Delivery{}
    |> Delivery.create_changeset(%{
      event_id: delivery.event_id,
      endpoint_id: delivery.endpoint_id,
      resend_of_id: delivery.id,
      status: "pending",
      triggered_by: actor,
      window_ends_at: DateTime.add(DateTime.utc_now(), endpoint.retry_window_seconds, :second)
    })
    |> Repo.insert()
  end

  defp insert_job(%Delivery{} = delivery) do
    %{delivery_id: delivery.id}
    |> Worker.new(queue: Queues.name(delivery.endpoint_id))
    |> Oban.insert()
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
