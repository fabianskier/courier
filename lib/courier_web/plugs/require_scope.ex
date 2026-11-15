defmodule CourierWeb.Plugs.RequireScope do
  @moduledoc """
  Requires the authenticated key to hold a scope.

      plug CourierWeb.Plugs.RequireScope, :read

  Must run after `CourierWeb.Plugs.Authenticate`. A key without the scope
  halts with `403` and error code `forbidden`. Scopes are independent:
  `write` does not imply `read`.
  """

  @behaviour Plug

  alias Courier.Access
  alias Courier.Access.ApiKey
  alias CourierWeb.Plugs.APIError

  @impl Plug
  def init(scope) when is_atom(scope) or is_binary(scope) do
    scope = to_string(scope)

    unless scope in ApiKey.scopes() do
      raise ArgumentError, "unknown scope #{inspect(scope)}"
    end

    scope
  end

  @impl Plug
  def call(%Plug.Conn{assigns: %{current_key: %ApiKey{} = key}} = conn, scope) do
    if Access.has_scope?(key, scope) do
      conn
    else
      forbidden(conn, scope)
    end
  end

  def call(conn, scope), do: forbidden(conn, scope)

  defp forbidden(conn, scope) do
    APIError.halt_with(conn, :forbidden, "forbidden", "This API key lacks the #{scope} scope.")
  end
end
