defmodule CourierWeb.MeControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import ExUnit.CaptureLog

  defp get_me(conn, authorization \\ nil) do
    conn =
      if authorization,
        do: put_req_header(conn, "authorization", authorization),
        else: conn

    get(conn, ~p"/api/v1/me")
  end

  defp assert_unauthorized(conn) do
    assert %{"error" => %{"code" => "unauthorized", "message" => message}} =
             json_response(conn, 401)

    assert is_binary(message) and message != ""
    assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
  end

  describe "Requirement: Authenticate API requests" do
    test "Scenario: Valid token", %{conn: conn} do
      %{token: token} = api_key_fixture()

      assert json_response(get_me(conn, "Bearer #{token}"), 200)
    end

    test "Scenario: Valid token (scheme is case-insensitive)", %{conn: conn} do
      %{token: token} = api_key_fixture()

      assert json_response(get_me(conn, "bearer #{token}"), 200)
    end

    test "Scenario: Missing token", %{conn: conn} do
      assert_unauthorized(get_me(conn))
    end

    test "Scenario: Unknown token", %{conn: conn} do
      token = "ck_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      assert_unauthorized(get_me(conn, "Bearer #{token}"))
    end

    test "Scenario: Malformed header", %{conn: conn} do
      %{token: token} = api_key_fixture()

      for header <- ["Basic abc", "Bearer", "Bearer ", "Bearer    ", token, "Token #{token}"] do
        assert_unauthorized(get_me(conn, header))
      end
    end
  end

  describe "Requirement: Revoke API keys" do
    test "Scenario: Revoked key no longer authenticates", %{conn: conn} do
      %{key: key, token: token} = api_key_fixture()
      assert json_response(get_me(conn, "Bearer #{token}"), 200)

      {:ok, _key} = Courier.Access.revoke_key(key.name)

      assert_unauthorized(get_me(build_conn(), "Bearer #{token}"))
    end
  end

  describe "Requirement: Identify the calling key" do
    test "Scenario: Who am I", %{conn: conn} do
      %{token: token} = api_key_fixture(%{name: "dashboard", scopes: ["read", "write"]})

      assert json_response(get_me(conn, "Bearer #{token}"), 200) == %{
               "name" => "dashboard",
               "scopes" => ["read", "write"]
             }
    end

    test "Scenario: Who am I (any scope may call it)", %{conn: conn} do
      %{token: token} = api_key_fixture(%{name: "producer", scopes: ["ingest"]})

      assert json_response(get_me(conn, "Bearer #{token}"), 200) == %{
               "name" => "producer",
               "scopes" => ["ingest"]
             }
    end
  end

  describe "Requirement: Consistent API error shape" do
    test "Scenario: Error body", %{conn: conn} do
      body = json_response(get_me(conn), 401)

      assert %{"error" => %{"code" => "unauthorized", "message" => message} = error} = body
      assert Map.keys(body) == ["error"]
      assert Enum.sort(Map.keys(error)) == ["code", "message"]
      assert is_binary(message) and message != ""
    end
  end

  describe "Requirement: Tokens never leak" do
    test "Scenario: Rejected token not echoed", %{conn: conn} do
      token = "ck_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      Logger.put_process_level(self(), :debug)
      on_exit(fn -> Logger.delete_process_level(self()) end)

      {conn, log} =
        with_log([level: :debug], fn -> get_me(conn, "Bearer #{token}") end)

      assert_unauthorized(conn)
      refute conn.resp_body =~ token
      refute log =~ token
    end
  end
end
