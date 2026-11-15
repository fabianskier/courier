defmodule Mix.Tasks.Courier.Keys.List do
  @shortdoc "Lists API keys without their tokens"

  @moduledoc """
  Lists all API keys, active and revoked, oldest first.

      $ mix courier.keys.list

  Each line shows the key's name, scopes, creation time and status (`active`
  or `revoked <time>`). Tokens and token hashes are never shown.
  """

  use Mix.Task

  alias Courier.Access

  @impl Mix.Task
  def run([]) do
    Mix.Courier.start_app()

    case Access.list_keys() do
      [] ->
        Mix.shell().info("No API keys.")

      keys ->
        shell = Mix.shell()

        [["NAME", "SCOPES", "CREATED", "STATUS"] | Enum.map(keys, &row/1)]
        |> format_table()
        |> Enum.each(&shell.info/1)
    end
  end

  def run(_args) do
    Mix.shell().error("Usage: mix courier.keys.list")
    exit({:shutdown, 1})
  end

  defp row(key) do
    [
      key.name,
      Enum.join(key.scopes, ","),
      format_time(key.inserted_at),
      status(key.revoked_at)
    ]
  end

  defp status(nil), do: "active"
  defp status(%DateTime{} = revoked_at), do: "revoked " <> format_time(revoked_at)

  defp format_time(%DateTime{} = time) do
    time |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp format_table(rows) do
    widths =
      rows
      |> Enum.zip_with(fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)

    Enum.map(rows, fn row ->
      row
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing(cell, width) end)
      |> String.trim_trailing()
    end)
  end
end
