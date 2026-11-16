defmodule CourierWeb.DeliveryController do
  @moduledoc """
  `/api/v1/deliveries`: show one delivery with its attempts and resends
  (`read` scope) and resend a terminal delivery as a new linked delivery
  (`write` scope).
  """

  use CourierWeb, :controller

  require Logger

  alias Courier.Delivery
  alias CourierWeb.Plugs.RequireScope

  action_fallback CourierWeb.FallbackController

  plug RequireScope, :read when action in [:show]
  plug RequireScope, :write when action in [:resend]

  def show(conn, %{"id" => id}) do
    with {:ok, delivery} <- Delivery.get_delivery(id) do
      render(conn, :show, delivery: delivery)
    end
  end

  def resend(conn, %{"id" => id}) do
    actor = "api_key:" <> conn.assigns.current_key.name

    with {:ok, resend} <- Delivery.resend(id, actor) do
      Logger.info(
        "resend delivery=#{resend.resend_of_id} new_delivery=#{resend.id} actor=#{actor}"
      )

      conn
      |> put_status(:accepted)
      |> render(:show, delivery: %{resend | attempts: [], resends: []})
    end
  end
end
