defmodule CourierWeb.Plugs.Authenticate do
  @moduledoc """
  Authenticates a request with `Authorization: Bearer <token>`.

  On success assigns the API key to `:current_key`. A missing or malformed
  header, an unknown token or a revoked key halts with `401`, error code
  `unauthorized` and a `www-authenticate: Bearer` header. The header and the
  token are never logged or echoed back.
  """

  @behaviour Plug

  import Plug.Conn

  alias CourierWeb.Plugs.APIError

  @message "A valid API key is required in the Authorization header as a Bearer token."

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, token} <- fetch_token(conn),
         {:ok, key} <- Courier.Access.authenticate(token) do
      assign(conn, :current_key, key)
    else
      _error ->
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> APIError.halt_with(:unauthorized, "unauthorized", @message)
    end
  end

  defp fetch_token(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme),
         token when token != "" <- String.trim(token) do
      {:ok, token}
    else
      _ -> :error
    end
  end
end
