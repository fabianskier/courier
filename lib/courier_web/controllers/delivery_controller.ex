defmodule CourierWeb.DeliveryController do
  @moduledoc """
  `/api/v1/deliveries`: show one delivery with its attempts. Needs the `read`
  scope.
  """

  use CourierWeb, :controller

  alias Courier.Delivery
  alias CourierWeb.Plugs.RequireScope

  action_fallback CourierWeb.FallbackController

  plug RequireScope, :read when action in [:show]

  def show(conn, %{"id" => id}) do
    with {:ok, delivery} <- Delivery.get_delivery(id) do
      render(conn, :show, delivery: delivery)
    end
  end
end
