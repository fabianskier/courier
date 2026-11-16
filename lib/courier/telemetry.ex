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
  | `[:courier, :delivery, :succeeded]` | `attempts`, `total_ms` | `delivery_id`, `endpoint_id` |
  | `[:courier, :delivery, :failed]` | `attempts`, `total_ms` | `delivery_id`, `endpoint_id`, `reason` |
  | `[:courier, :delivery, :retry_scheduled]` | `delay_seconds` | `delivery_id`, `endpoint_id`, `attempt` |

  `total_ms` is the time from the delivery's `inserted_at` to its
  `completed_at`.
  """

  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event

  @event_ingested [:courier, :event, :ingested]
  @delivery_succeeded [:courier, :delivery, :succeeded]
  @delivery_failed [:courier, :delivery, :failed]
  @delivery_retry_scheduled [:courier, :delivery, :retry_scheduled]

  @type failure_reason :: :non_retryable | :window_ended

  @doc "The telemetry events emitted through this module."
  @spec events() :: [[atom()]]
  def events do
    [@event_ingested, @delivery_succeeded, @delivery_failed, @delivery_retry_scheduled]
  end

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
