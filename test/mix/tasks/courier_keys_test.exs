defmodule Mix.Tasks.Courier.KeysTest do
  # Mix.shell/1 is global, so these tests cannot run concurrently.
  use Courier.DataCase, async: false

  import Courier.AccessFixtures

  alias Courier.Access
  alias Courier.Access.ApiKey
  alias Mix.Tasks.Courier.Keys

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp collect_output(acc \\ []) do
    receive do
      {:mix_shell, kind, [line]} when kind in [:info, :error] ->
        collect_output([{kind, line} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp lines(output, kind) do
    for {^kind, line} <- output, do: line
  end

  describe "Requirement: Manage keys from the command line" do
    test "Scenario: Create from the command line" do
      Keys.Create.run(["--name", "producer", "--scopes", "ingest"])

      info = collect_output() |> lines(:info) |> Enum.join("\n")

      assert [%ApiKey{name: "producer", scopes: ["ingest"]} = key] = Access.list_keys()
      assert [token] = Regex.run(~r/ck_[A-Za-z0-9_-]+/, info)
      assert {:ok, %ApiKey{id: id}} = Access.authenticate(token)
      assert id == key.id
      assert info =~ "cannot be shown again"
    end

    test "Scenario: Invalid input from the command line" do
      assert catch_exit(Keys.Create.run(["--name", "producer", "--scopes", "ingest,admin"])) ==
               {:shutdown, 1}

      errors = collect_output() |> lines(:error) |> Enum.join("\n")
      assert errors =~ "scopes"
      assert Access.list_keys() == []
    end

    test "Scenario: List and revoke from the command line" do
      %{token: token} = api_key_fixture(%{name: "producer", scopes: ["ingest"]})
      %{token: other_token} = api_key_fixture(%{name: "dashboard", scopes: ["read", "write"]})

      Keys.Revoke.run(["producer"])
      assert collect_output() |> lines(:info) |> Enum.join() =~ "Revoked"

      Keys.List.run([])

      output = collect_output() |> lines(:info) |> Enum.join("\n")
      [producer_line] = output |> String.split("\n") |> Enum.filter(&(&1 =~ "producer"))
      [dashboard_line] = output |> String.split("\n") |> Enum.filter(&(&1 =~ "dashboard"))

      assert producer_line =~ "revoked"
      assert dashboard_line =~ "active"
      refute output =~ token
      refute output =~ other_token
      refute output =~ "ck_"
      assert Access.authenticate(token) == {:error, :unauthorized}
    end
  end

  describe "command line errors" do
    test "create without required options exits with status 1" do
      assert catch_exit(Keys.Create.run(["--name", "producer"])) == {:shutdown, 1}
      assert collect_output() |> lines(:error) |> Enum.join() =~ "Usage"
    end

    test "create with a duplicate name exits with status 1" do
      api_key_fixture(%{name: "producer"})

      assert catch_exit(Keys.Create.run(["--name", "producer", "--scopes", "read"])) ==
               {:shutdown, 1}

      assert collect_output() |> lines(:error) |> Enum.join("\n") =~ "name"
    end

    test "revoke an unknown name exits with status 1" do
      assert catch_exit(Keys.Revoke.run(["missing"])) == {:shutdown, 1}
      assert collect_output() |> lines(:error) |> Enum.join() =~ "not found"
    end

    test "list with no keys says so" do
      Keys.List.run([])
      assert collect_output() |> lines(:info) == ["No API keys."]
    end
  end
end
