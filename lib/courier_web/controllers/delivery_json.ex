defmodule CourierWeb.DeliveryJSON do
  @moduledoc """
  JSON rendering for deliveries: `{"data": [...], "next_cursor": ...}` for a
  page of deliveries without attempts, and `{"data": ...}` for one delivery
  with its event type, merchant id, creation time, status, timing, resend
  links (`resend_of_id`, `triggered_by` and its direct `resends`, oldest
  first) and attempts in order. Attempt request headers are never rendered.
  """

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event

  @doc "Renders a page of deliveries with their preloaded events, without attempts."
  def index(%{page: %{items: items, next_cursor: next_cursor}}) do
    %{data: Enum.map(items, &summary/1), next_cursor: next_cursor}
  end

  @doc "Renders one delivery with its preloaded event, attempts and resends."
  def show(%{delivery: delivery}), do: %{data: data(delivery)}

  defp data(%Delivery{} = delivery) do
    delivery
    |> summary()
    |> Map.merge(%{
      window_ends_at: iso8601(delivery.window_ends_at),
      resends: Enum.map(delivery.resends, &resend/1),
      attempts: Enum.map(delivery.attempts, &attempt/1)
    })
  end

  defp summary(%Delivery{} = delivery) do
    %{
      id: delivery.id,
      event_id: delivery.event_id,
      event_type: event_field(delivery.event, :type),
      merchant_id: event_field(delivery.event, :merchant_id),
      endpoint_id: delivery.endpoint_id,
      status: delivery.status,
      attempt_count: delivery.attempt_count,
      next_attempt_at: iso8601(delivery.next_attempt_at),
      completed_at: iso8601(delivery.completed_at),
      resend_of_id: delivery.resend_of_id,
      triggered_by: delivery.triggered_by,
      inserted_at: iso8601(delivery.inserted_at)
    }
  end

  # The event is preloaded by reads and lists; a fresh resend may not carry it.
  defp event_field(%Event{} = event, field), do: Map.fetch!(event, field)
  defp event_field(_not_loaded, _field), do: nil

  defp resend(%Delivery{} = resend) do
    %{
      id: resend.id,
      status: resend.status,
      triggered_by: resend.triggered_by,
      inserted_at: iso8601(resend.inserted_at)
    }
  end

  defp attempt(%Attempt{} = attempt) do
    %{
      number: attempt.number,
      started_at: iso8601(attempt.started_at),
      duration_ms: attempt.duration_ms,
      url: attempt.url,
      response_status: attempt.response_status,
      response_body: attempt.response_body,
      error: attempt.error
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
