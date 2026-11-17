defmodule CourierMCP.Tools.GetEndpointHealth do
  @moduledoc """
  Returns the health of one endpoint by id: whether it is enabled, its
  consecutive failed attempts, whether it is degraded and since when, and how
  many of its deliveries are pending, succeeded, failed or skipped. Use it to
  find out whether failures come from the merchant's endpoint.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "get_endpoint_health",
    annotations: %{"readOnlyHint" => true}

  alias CourierMCP.Call
  alias CourierMCP.Views

  schema do
    field(:id, :string, required: true, description: "The endpoint id (a UUID)")
  end

  @impl true
  def execute(%{id: id}, frame) do
    Call.run("get_endpoint_health", frame, %{id: id}, fn ->
      case Courier.Endpoints.get_endpoint(id) do
        {:ok, endpoint} ->
          {:ok, Views.endpoint_health(endpoint, Courier.Delivery.count_by_status(endpoint.id))}

        {:error, :not_found} ->
          {:error, "not_found",
           "No endpoint has this id. Check the id, or take the endpoint_id of a delivery."}
      end
    end)
  end
end
