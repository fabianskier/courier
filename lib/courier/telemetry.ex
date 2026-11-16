defmodule Courier.Telemetry do
  @moduledoc """
  The names of courier's telemetry events and helpers to emit them, so the
  names live in one place.

  Events are emitted after the data is committed. Measurements and metadata
  hold counts, durations and ids only: never payloads, response bodies,
  headers or secrets.

  | Event | Measurements | Metadata |
  |---|---|---|
  | `[:courier, :event, :ingested]` | `deliveries`, `pending` | `merchant_id`, `type` |
  | `[:courier, :attempt, :start]` | `system_time`, `monotonic_time` | `delivery_id`, `endpoint_id`, `number` |
  | `[:courier, :attempt, :stop]` | `duration`, `since_created_ms` | the start metadata plus `outcome`, `status`, `status_class` |
  | `[:courier, :attempt, :exception]` | `duration` | the start metadata plus `kind`, `reason`, `stacktrace` |
  | `[:courier, :delivery, :succeeded]` | `attempts`, `total_ms` | `delivery_id`, `endpoint_id` |
  | `[:courier, :delivery, :failed]` | `attempts`, `total_ms` | `delivery_id`, `endpoint_id`, `reason` |
  | `[:courier, :delivery, :retry_scheduled]` | `delay_seconds` | `delivery_id`, `endpoint_id`, `attempt` |
  | `[:courier, :queue, :lag]` | `seconds`, `available` | `queue` |

  `total_ms` is the time from the delivery's `inserted_at` to its
  `completed_at`. `since_created_ms` is the time from `inserted_at` to the
  start of the attempt; for attempt 1 it is the time to first attempt.
  Attempt durations are in native time units.
  """

  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event

  @attempt [:courier, :attempt]
  @event_ingested [:courier, :event, :ingested]
  @delivery_succeeded [:courier, :delivery, :succeeded]
  @delivery_failed [:courier, :delivery, :failed]
  @delivery_retry_scheduled [:courier, :delivery, :retry_scheduled]
  @queue_lag [:courier, :queue, :lag]

  @type failure_reason :: :non_retryable | :window_ended
  @type attempt_outcome :: :success | :retry | :give_up
  @type attempt_result :: {:ok, %{status: integer()}} | {:error, term()}

  @doc "The telemetry events emitted through this module."
  @spec events() :: [[atom()]]
  def events do
    [@event_ingested, @delivery_succeeded, @delivery_failed, @delivery_retry_scheduled]
  end

  @doc """
  The attempt events, emitted by `span_attempt/3`. They are listed apart from
  `events/0`, which holds the events emitted once per committed change.
  """
  @spec attempt_events() :: [[atom()]]
  def attempt_events do
    [@attempt ++ [:start], @attempt ++ [:stop], @attempt ++ [:exception]]
  end

  @doc """
  Runs `fun`, which sends the request of `delivery`'s next attempt, inside a
  `[:courier, :attempt]` span that started at `started_at`.

  `fun` returns `{result, outcome}`: the client's result and how the retry
  policy classified it. Only the status of `result` reaches the metadata.
  Returns what `fun` returned.
  """
  @spec span_attempt(Delivery.t(), DateTime.t(), (-> {attempt_result(), attempt_outcome()})) ::
          {attempt_result(), attempt_outcome()}
  def span_attempt(%Delivery{} = delivery, %DateTime{} = started_at, fun)
      when is_function(fun, 0) do
    start_metadata = Map.put(ids(delivery), :number, delivery.attempt_count + 1)

    extra_measurements = %{
      since_created_ms: DateTime.diff(started_at, delivery.inserted_at, :millisecond)
    }

    :telemetry.span(@attempt, start_metadata, fn ->
      {result, outcome} = fun.()
      status = status(result)

      stop_metadata =
        Map.merge(start_metadata, %{
          outcome: outcome,
          status: status,
          status_class: status_class(status)
        })

      {{result, outcome}, extra_measurements, stop_metadata}
    end)
  end

  defp status({:ok, %{status: status}}) when is_integer(status), do: status
  defp status(_error), do: nil

  defp status_class(status) when is_integer(status), do: "#{div(status, 100)}xx"
  defp status_class(nil), do: "error"

  @doc """
  Emits `[:courier, :event, :ingested]` for a new `event` stored with
  `deliveries`.
  """
  @spec emit_event_ingested(Event.t(), [Delivery.t()]) :: :ok
  def emit_event_ingested(%Event{} = event, deliveries) when is_list(deliveries) do
    :telemetry.execute(
      @event_ingested,
      %{
        deliveries: length(deliveries),
        pending: Enum.count(deliveries, &(&1.status == "pending"))
      },
      %{merchant_id: event.merchant_id, type: event.type}
    )
  end

  @doc "Emits `[:courier, :delivery, :succeeded]` for a delivery that succeeded."
  @spec emit_delivery_succeeded(Delivery.t()) :: :ok
  def emit_delivery_succeeded(%Delivery{} = delivery) do
    :telemetry.execute(@delivery_succeeded, completed(delivery), ids(delivery))
  end

  @doc "Emits `[:courier, :delivery, :failed]` for a delivery that failed for `reason`."
  @spec emit_delivery_failed(Delivery.t(), failure_reason()) :: :ok
  def emit_delivery_failed(%Delivery{} = delivery, reason)
      when reason in [:non_retryable, :window_ended] do
    :telemetry.execute(
      @delivery_failed,
      completed(delivery),
      Map.put(ids(delivery), :reason, reason)
    )
  end

  @doc """
  Emits `[:courier, :delivery, :retry_scheduled]` for a delivery whose next
  attempt is `delay_seconds` away; `attempt` is the number of the attempt
  that failed.
  """
  @spec emit_delivery_retry_scheduled(Delivery.t(), non_neg_integer()) :: :ok
  def emit_delivery_retry_scheduled(%Delivery{} = delivery, delay_seconds)
      when is_integer(delay_seconds) do
    :telemetry.execute(
      @delivery_retry_scheduled,
      %{delay_seconds: delay_seconds},
      Map.put(ids(delivery), :attempt, delivery.attempt_count)
    )
  end

  @doc """
  The queue lag event, emitted by `emit_queue_lag/3`. It is listed apart from
  `events/0` because it is a periodic measurement, not a committed change.
  """
  @spec queue_lag_event() :: [atom()]
  def queue_lag_event, do: @queue_lag

  @doc """
  Emits `[:courier, :queue, :lag]` for `queue`: its oldest available job has
  been runnable for `seconds`, and `available` jobs are waiting.
  """
  @spec emit_queue_lag(String.t(), number(), non_neg_integer()) :: :ok
  def emit_queue_lag(queue, seconds, available)
      when is_binary(queue) and is_number(seconds) and is_integer(available) do
    :telemetry.execute(@queue_lag, %{seconds: seconds, available: available}, %{queue: queue})
  end

  defp completed(%Delivery{} = delivery) do
    %{
      attempts: delivery.attempt_count,
      total_ms: DateTime.diff(delivery.completed_at, delivery.inserted_at, :millisecond)
    }
  end

  defp ids(%Delivery{} = delivery) do
    %{delivery_id: delivery.id, endpoint_id: delivery.endpoint_id}
  end
end
