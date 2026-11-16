defmodule CourierWeb.EventJSON do
  @moduledoc """
  JSON rendering for events: `{"data": ...}` with the event and its
  deliveries (`id`, `endpoint_id`, `status`, `window_ends_at`), and
  `{"data": [...], "next_cursor": ...}` for a page of events without their
  deliveries. The idempotency key and request hash are never rendered.
  """

  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event

  @doc "Renders a page of events, without deliveries."
  def index(%{page: %{items: items, next_cursor: next_cursor}}) do
    %{data: Enum.map(items, &summary/1), next_cursor: next_cursor}
  end

  @doc "Renders one event with its preloaded deliveries."
  def show(%{event: event}), do: %{data: data(event)}

  defp data(%Event{} = event) do
    Map.put(summary(event), :deliveries, Enum.map(event.deliveries, &delivery/1))
  end

  defp summary(%Event{} = event) do
    %{
      id: event.id,
      type: event.type,
      merchant_id: event.merchant_id,
      payload: event.payload,
      occurred_at: iso8601(event.occurred_at),
      received_at: iso8601(event.received_at)
    }
  end

  defp delivery(%Delivery{} = delivery) do
    %{
      id: delivery.id,
      endpoint_id: delivery.endpoint_id,
      status: delivery.status,
      window_ends_at: iso8601(delivery.window_ends_at)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
