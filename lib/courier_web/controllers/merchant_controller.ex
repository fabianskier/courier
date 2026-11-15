defmodule CourierWeb.MerchantController do
  @moduledoc """
  `/api/v1/merchants`: list, show, create and update merchants. Listing and
  showing need the `read` scope; creating and updating need `write`.
  """

  use CourierWeb, :controller

  alias Courier.Merchants
  alias CourierWeb.Params
  alias CourierWeb.Plugs.RequireScope

  action_fallback CourierWeb.FallbackController

  plug RequireScope, :read when action in [:index, :show]
  plug RequireScope, :write when action in [:create, :update]

  def index(conn, params) do
    with {:ok, opts} <- Params.pagination(params),
         {:ok, page} <- Merchants.list_merchants(opts) do
      render(conn, :index, page: page)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, merchant} <- Merchants.get_merchant(id) do
      render(conn, :show, merchant: merchant)
    end
  end

  def create(conn, params) do
    with {:ok, merchant} <- Merchants.create_merchant(Map.take(params, ["name"])) do
      conn
      |> put_status(:created)
      |> render(:show, merchant: merchant)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, merchant} <- Merchants.get_merchant(id),
         {:ok, merchant} <-
           Merchants.update_merchant(merchant, Map.take(params, ["name", "enabled"])) do
      render(conn, :show, merchant: merchant)
    end
  end
end
