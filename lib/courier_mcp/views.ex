defmodule CourierMCP.Views do
  @moduledoc """
  Plain maps for tool results: ids, statuses and ISO 8601 timestamps. No
  secrets and no request headers; stored external data is wrapped by
  `CourierMCP.Untrusted`.
  """

  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event
  alias CourierMCP.Untrusted

  @payload_max_chars 2_000

  @doc "An event with its preloaded deliveries."
  @spec event(Event.t()) :: map()
  def event(%Event{} = event) do
    %{
      id: event.id,
      type: event.type,
      merchant_id: event.merchant_id,
      created_at: iso8601(event.inserted_at),
      payload: Untrusted.wrap(event.payload, @payload_max_chars),
      deliveries: Enum.map(event.deliveries, &event_delivery/1)
    }
  end

  defp event_delivery(%Delivery{} = delivery) do
    %{
      id: delivery.id,
      endpoint_id: delivery.endpoint_id,
      status: delivery.status,
      attempt_count: delivery.attempt_count,
      resend_of_id: delivery.resend_of_id
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
