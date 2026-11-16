defmodule CourierWeb.DeliveryJSON do
  @moduledoc """
  JSON rendering for a delivery: `{"data": ...}` with its status, timing,
  resend links (`resend_of_id`, `triggered_by` and its direct `resends`,
  oldest first) and attempts in order. Attempt request headers are never
  rendered.
  """

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery

  @doc "Renders one delivery with its preloaded attempts and resends."
  def show(%{delivery: delivery}), do: %{data: data(delivery)}

  defp data(%Delivery{} = delivery) do
    %{
      id: delivery.id,
      event_id: delivery.event_id,
      endpoint_id: delivery.endpoint_id,
      status: delivery.status,
      attempt_count: delivery.attempt_count,
      next_attempt_at: iso8601(delivery.next_attempt_at),
      window_ends_at: iso8601(delivery.window_ends_at),
      completed_at: iso8601(delivery.completed_at),
      resend_of_id: delivery.resend_of_id,
      triggered_by: delivery.triggered_by,
      resends: Enum.map(delivery.resends, &resend/1),
      attempts: Enum.map(delivery.attempts, &attempt/1)
    }
  end

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
