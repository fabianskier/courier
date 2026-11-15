defmodule Courier.AccessFixtures do
  @moduledoc """
  Test helpers for creating API keys through `Courier.Access`.
  """

  @doc """
  Creates an API key and returns `%{key: key, token: token}`.

  Defaults to a unique name and the `read` scope.
  """
  def api_key_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "key-#{System.unique_integer([:positive])}",
        scopes: ["read"]
      })

    {:ok, %{key: _key, token: _token} = result} = Courier.Access.create_key(attrs)
    result
  end
end
