defmodule CourierWeb.Plugs.APIError do
  @moduledoc """
  Sends an API error rendered by `CourierWeb.APIErrorJSON` and halts the conn.
  """

  import Plug.Conn

  alias CourierWeb.APIErrorJSON

  @doc "Responds with `status` and the error body for `code` and `message`."
  @spec halt_with(Plug.Conn.t(), Plug.Conn.status(), String.t(), String.t()) :: Plug.Conn.t()
  def halt_with(conn, status, code, message) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(APIErrorJSON.error(%{code: code, message: message}))
    |> halt()
  end
end
