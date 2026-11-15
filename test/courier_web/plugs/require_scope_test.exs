defmodule CourierWeb.Plugs.RequireScopeTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures

  alias CourierWeb.Plugs.RequireScope

  defp run(conn, key, scope) do
    conn
    |> assign(:current_key, key)
    |> RequireScope.call(RequireScope.init(scope))
  end

  describe "Requirement: Authorize by scope" do
    test "Scenario: Key with the required scope", %{conn: conn} do
      %{key: key} = api_key_fixture(%{scopes: ["read"]})

      conn = run(conn, key, :read)

      refute conn.halted
      assert conn.status == nil
    end

    test "Scenario: Key without the required scope", %{conn: conn} do
      %{key: key} = api_key_fixture(%{scopes: ["read"]})

      conn = run(conn, key, :write)

      assert conn.halted

      assert %{"error" => %{"code" => "forbidden", "message" => message}} =
               json_response(conn, 403)

      assert is_binary(message) and message != ""
    end

    test "Scenario: Key without the required scope (write does not imply read)", %{conn: conn} do
      %{key: key} = api_key_fixture(%{scopes: ["write"]})

      conn = run(conn, key, "read")

      assert conn.halted
      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end

    test "rejects a conn without an authenticated key", %{conn: conn} do
      conn = RequireScope.call(conn, RequireScope.init(:read))

      assert conn.halted
      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end

    test "init/1 rejects unknown scopes" do
      assert_raise ArgumentError, fn -> RequireScope.init(:admin) end
    end
  end
end
