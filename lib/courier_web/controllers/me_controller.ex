defmodule CourierWeb.MeController do
  @moduledoc """
  `GET /api/v1/me`: the name and scopes of the calling key.
  """

  use CourierWeb, :controller

  def show(conn, _params) do
    key = conn.assigns.current_key
    json(conn, %{name: key.name, scopes: key.scopes})
  end
end
