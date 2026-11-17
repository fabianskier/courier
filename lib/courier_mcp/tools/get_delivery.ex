defmodule CourierMCP.Tools.GetDelivery do
  @moduledoc """
  Returns one delivery by id: its status, attempt count, next attempt, window
  end and who triggered it, its attempts in order (response status, error,
  duration, and the response body as untrusted data) and its resends. Use it
  to find out why a delivery failed.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "get_delivery",
    annotations: %{"readOnlyHint" => true}

  alias CourierMCP.Call
  alias CourierMCP.Views

  schema do
    field(:id, :string, required: true, description: "The delivery id (a UUID)")
  end

  @impl true
  def execute(%{id: id}, frame) do
    Call.run("get_delivery", frame, %{id: id}, fn ->
      case Courier.Delivery.get_delivery(id) do
        {:ok, delivery} ->
          {:ok, Views.delivery(delivery)}

        {:error, :not_found} ->
          {:error, "not_found",
           "No delivery has this id. Check the id, or find it with list_deliveries."}
      end
    end)
  end
end
