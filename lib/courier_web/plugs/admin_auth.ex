defmodule CourierWeb.Plugs.AdminAuth do
  @moduledoc """
  Lets only an admin through, with HTTP Basic credentials whose password is
  the admin token (`config :courier, :admin_token`). The user name is ignored.

  When no admin token is configured the request halts with `404`, so the
  route is hidden. Missing credentials or a wrong password halt with `401`
  and a `www-authenticate` header. The password is compared in constant
  time. The token and the `authorization` header are never logged or echoed
  back.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case admin_token() do
      nil ->
        conn
        |> send_resp(:not_found, "Not Found")
        |> halt()

      token ->
        with {_user, password} <- Plug.BasicAuth.parse_basic_auth(conn),
             true <- Plug.Crypto.secure_compare(password, token) do
          conn
        else
          _mismatch ->
            conn
            |> Plug.BasicAuth.request_basic_auth()
            |> halt()
        end
    end
  end

  # An empty token counts as not configured: it must never authenticate.
  defp admin_token do
    case Application.get_env(:courier, :admin_token) do
      token when is_binary(token) and token != "" -> token
      _other -> nil
    end
  end
end
