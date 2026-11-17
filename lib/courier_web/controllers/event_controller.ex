defmodule CourierWeb.EventController do
  @moduledoc """
  `/api/v1/events`: ingest, list and show events. Creating needs the `ingest`
  scope and an `Idempotency-Key` header; a new event answers `202` and a
  repeat `200`. Listing (newest first, filtered by `merchant_id`, `type` and
  a `since`/`until` range on the received time) and showing need the `read`
  scope.
  """

  use CourierWeb, :controller

  alias Courier.Ingestion
  alias CourierWeb.Params
  alias CourierWeb.Plugs.RequireScope

  @create_fields ~w(type merchant_id payload occurred_at)

  action_fallback CourierWeb.FallbackController

  plug RequireScope, :ingest when action in [:create]
  plug RequireScope, :read when action in [:index, :show]

  def index(conn, params) do
    with {:ok, opts} <- Params.pagination(params),
         {:ok, range} <- Params.time_range(params),
         {:ok, page} <-
           opts
           |> Map.merge(range)
           |> Map.merge(%{merchant_id: params["merchant_id"], type: params["type"]})
           |> Ingestion.list_events() do
      render(conn, :index, page: page)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, event} <- Ingestion.get_event(id) do
      render(conn, :show, event: event)
    end
  end

  def create(conn, params) do
    key = conn |> get_req_header("idempotency-key") |> List.first()

    with {:ok, result, event} <- Ingestion.ingest(Map.take(params, @create_fields), key) do
      conn
      |> put_status(status(result))
      |> render(:show, event: event)
    end
  end

  defp status(:created), do: :accepted
  defp status(:repeat), do: :ok
end
