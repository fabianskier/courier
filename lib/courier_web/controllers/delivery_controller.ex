defmodule CourierWeb.DeliveryController do
  @moduledoc """
  `/api/v1/deliveries`: list deliveries newest first, filtered by `status`,
  `merchant_id`, `endpoint_id`, `event_id`, `event_type` and a
  `since`/`until` range on the creation time, and show one delivery with its
  attempts and resends (both `read` scope); resend a terminal delivery as a
  new linked delivery (`write` scope).
  """

  use CourierWeb, :controller

  require Logger

  alias Courier.Delivery
  alias Courier.Delivery.Delivery, as: DeliverySchema
  alias CourierWeb.Params
  alias CourierWeb.Plugs.RequireScope

  action_fallback CourierWeb.FallbackController

  plug RequireScope, :read when action in [:index, :show]
  plug RequireScope, :write when action in [:resend]

  def index(conn, params) do
    with {:ok, page_opts} <- Params.pagination(params),
         {:ok, range} <- Params.time_range(params),
         {:ok, status} <- status_filter(params["status"]),
         {:ok, page} <-
           page_opts
           |> Map.merge(range)
           |> Map.merge(%{
             status: status,
             merchant_id: params["merchant_id"],
             endpoint_id: params["endpoint_id"],
             event_id: params["event_id"],
             event_type: params["event_type"]
           })
           |> Delivery.list_deliveries() do
      render(conn, :index, page: page)
    end
  end

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

  defp status_filter(nil), do: {:ok, nil}

  defp status_filter(status) do
    if status in DeliverySchema.statuses(),
      do: {:ok, status},
      else: {:error, {:invalid_param, "status"}}
  end
end
