defmodule CourierWeb.DashboardSocket do
  @moduledoc """
  The dashboard's WebSocket at `/socket`.

  Clients authenticate with an API key that has the `read` scope, sent as the
  WebSocket auth token (the `Sec-WebSocket-Protocol` header), so the key never
  appears in a URL or a log. Anything else is refused.
  """

  use Phoenix.Socket

  alias Courier.Access

  channel "dashboard:*", CourierWeb.DashboardChannel

  @impl true
  def connect(_params, socket, %{auth_token: token}) when is_binary(token) do
    with {:ok, key} <- Access.authenticate(token),
         true <- Access.has_scope?(key, :read) do
      {:ok, assign(socket, :api_key_id, key.id)}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
