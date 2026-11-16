defmodule CourierWeb.EventController do
  @moduledoc """
  `/api/v1/events`: ingest events. Creating needs the `ingest` scope and an
  `Idempotency-Key` header; a new event answers `202` and a repeat `200`.
  """

  use CourierWeb, :controller

  alias Courier.Ingestion
  alias CourierWeb.Plugs.RequireScope

  @create_fields ~w(type merchant_id payload occurred_at)

  action_fallback CourierWeb.FallbackController

  plug RequireScope, :ingest when action in [:create]

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
