defmodule CourierMCP.Views do
  @moduledoc """
  Plain maps for tool results: ids, statuses and ISO 8601 timestamps. No
  secrets and no request headers; stored external data is wrapped by
  `CourierMCP.Untrusted`.
  """

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event
  alias CourierMCP.Untrusted

  @payload_max_chars 2_000
  @response_body_max_chars 500

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

  @doc "A delivery with its preloaded attempts (in order) and resends."
  @spec delivery(Delivery.t()) :: map()
  def delivery(%Delivery{} = delivery) do
    delivery
    |> delivery_summary()
    |> Map.merge(%{
      attempts: Enum.map(delivery.attempts, &attempt/1),
      resends: Enum.map(delivery.resends, &delivery_summary/1)
    })
  end

  @doc "A page of deliveries, without attempts, and the cursor of the next page."
  @spec delivery_page(Courier.Pagination.page()) :: map()
  def delivery_page(%{items: items, next_cursor: next_cursor}) do
    %{deliveries: Enum.map(items, &delivery_summary/1), next_cursor: next_cursor}
  end

  defp delivery_summary(%Delivery{} = delivery) do
    %{
      id: delivery.id,
      event_id: delivery.event_id,
      endpoint_id: delivery.endpoint_id,
      status: delivery.status,
      attempt_count: delivery.attempt_count,
      next_attempt_at: iso8601(delivery.next_attempt_at),
      window_ends_at: iso8601(delivery.window_ends_at),
      completed_at: iso8601(delivery.completed_at),
      triggered_by: delivery.triggered_by,
      resend_of_id: delivery.resend_of_id,
      created_at: iso8601(delivery.inserted_at)
    }
  end

  # No url and no request headers: the attempt's request is not exposed.
  defp attempt(%Attempt{} = attempt) do
    %{
      number: attempt.number,
      started_at: iso8601(attempt.started_at),
      duration_ms: attempt.duration_ms,
      response_status: attempt.response_status,
      error: attempt.error,
      response_body: Untrusted.wrap(attempt.response_body, @response_body_max_chars)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
