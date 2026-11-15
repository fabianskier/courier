defmodule Mix.Tasks.Courier.Keys.Create do
  @shortdoc "Creates an API key and prints its token once"

  @moduledoc """
  Creates an API key with a unique name and one or more scopes.

      $ mix courier.keys.create --name NAME --scopes SCOPE[,SCOPE...]

  Scopes are a comma-separated list of `ingest`, `read` and `write`.

  The plaintext token is printed once and cannot be shown again; only its hash
  is stored. Invalid input prints the errors and exits with status 1.

  ## Example

      $ mix courier.keys.create --name dashboard --scopes read,write
  """

  use Mix.Task

  alias Courier.Access

  @switches [name: :string, scopes: :string]

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} -> create(opts)
      _invalid -> usage_error()
    end
  end

  defp create(opts) do
    with {:ok, name} <- Keyword.fetch(opts, :name),
         {:ok, scopes} <- Keyword.fetch(opts, :scopes) do
      Mix.Courier.start_app()

      case Access.create_key(%{name: name, scopes: parse_scopes(scopes)}) do
        {:ok, %{key: key, token: token}} ->
          Mix.shell().info("""
          Created key #{inspect(key.name)} with scopes: #{Enum.join(key.scopes, ", ")}

          Token: #{token}

          Store this token now. It cannot be shown again.\
          """)

        {:error, changeset} ->
          Mix.shell().error("Could not create key:")

          changeset
          |> format_errors()
          |> Enum.each(&Mix.shell().error("  " <> &1))

          exit({:shutdown, 1})
      end
    else
      :error -> usage_error()
    end
  end

  defp parse_scopes(scopes) do
    scopes
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, &"#{field} #{&1}")
    end)
  end

  defp usage_error do
    Mix.shell().error("Usage: mix courier.keys.create --name NAME --scopes SCOPE[,SCOPE...]")
    exit({:shutdown, 1})
  end
end
