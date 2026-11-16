defmodule CourierWeb.EndpointController do
  @moduledoc """
  `/api/v1/endpoints`: list, show, create and update endpoints and rotate their
  signing secrets. Listing and showing need the `read` scope; creating,
  updating and rotating need `write`. Only create and rotate return a secret.
  """

  use CourierWeb, :controller

  alias Courier.Endpoints
  alias CourierWeb.Params
  alias CourierWeb.Plugs.RequireScope

  @create_fields ~w(merchant_id url description event_types retry_window_seconds retry_on_4xx max_concurrency)
  @update_fields ~w(url description event_types enabled retry_window_seconds retry_on_4xx max_concurrency)

  action_fallback CourierWeb.FallbackController

  plug RequireScope, :read when action in [:index, :show]
  plug RequireScope, :write when action in [:create, :update, :rotate_secret]

  def index(conn, params) do
    with {:ok, opts} <- Params.pagination(params),
         {:ok, page} <-
           opts
           |> Map.put(:merchant_id, params["merchant_id"])
           |> Map.put(:degraded, degraded_filter(params["degraded"]))
           |> Endpoints.list_endpoints() do
      render(conn, :index, page: page)
    end
  end

  # Only "true" and "false" filter; any other value is ignored.
  defp degraded_filter("true"), do: true
  defp degraded_filter("false"), do: false
  defp degraded_filter(_), do: nil

  def show(conn, %{"id" => id}) do
    with {:ok, endpoint} <- Endpoints.get_endpoint(id) do
      render(conn, :show, endpoint: endpoint)
    end
  end

  def create(conn, params) do
    with {:ok, endpoint, secret} <- Endpoints.create_endpoint(Map.take(params, @create_fields)) do
      conn
      |> put_status(:created)
      |> render(:show_with_secret, endpoint: endpoint, secret: secret)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, endpoint} <- Endpoints.get_endpoint(id),
         {:ok, endpoint} <- Endpoints.update_endpoint(endpoint, Map.take(params, @update_fields)) do
      render(conn, :show, endpoint: endpoint)
    end
  end

  def rotate_secret(conn, %{"id" => id}) do
    with {:ok, endpoint} <- Endpoints.get_endpoint(id),
         {:ok, endpoint, secret} <- Endpoints.rotate_secret(endpoint) do
      render(conn, :show_with_secret, endpoint: endpoint, secret: secret)
    end
  end
end
