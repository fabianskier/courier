defmodule Mix.Tasks.Courier.Keys.Revoke do
  @shortdoc "Revokes an API key by name"

  @moduledoc """
  Revokes the API key named `NAME`. The key stops authenticating at once and
  stays in the listing as revoked.

      $ mix courier.keys.revoke NAME

  Revoking an already revoked key keeps its original revocation time. An
  unknown name prints an error and exits with status 1.
  """

  use Mix.Task

  alias Courier.Access

  @impl Mix.Task
  def run([name]) do
    Mix.Task.run("app.start")

    case Access.revoke_key(name) do
      {:ok, key} ->
        Mix.shell().info("Revoked key #{inspect(key.name)}.")

      {:error, :not_found} ->
        Mix.shell().error("Key #{inspect(name)} not found.")
        exit({:shutdown, 1})
    end
  end

  def run(_args) do
    Mix.shell().error("Usage: mix courier.keys.revoke NAME")
    exit({:shutdown, 1})
  end
end
