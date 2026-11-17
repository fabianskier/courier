defmodule CourierMCP.EndpointTest do
  # The MCP session runs in its own process (shared sandbox) and one test
  # captures the log at a lowered global level.
  use CourierWeb.ConnCase, async: false

  import Courier.AccessFixtures
  import Courier.EventsFixtures

  alias CourierMCP.Client

  describe "Requirement: Authenticated MCP endpoint" do
    test "Scenario: Missing key rejected" do
      conn = Client.initialize(nil)

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "Scenario: Key without read rejected" do
      %{token: token} = api_key_fixture(scopes: ["ingest"])

      conn = Client.initialize(token)

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end

    test "Scenario: Session initialized" do
      %{token: token} = api_key_fixture()

      conn = Client.initialize(token)

      assert %{"result" => result} = json_response(conn, 200)
      assert result["serverInfo"]["name"] == "courier"
      assert is_map(result["capabilities"]["tools"])
      assert [_session_id] = get_resp_header(conn, "mcp-session-id")
    end

    test "a request on an open session without a key is rejected" do
      %{token: token} = api_key_fixture()
      session = Client.connect(token)

      conn = Client.request(nil, session.id, "tools/list")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "the tools are listed with a description and an input schema" do
      %{token: token} = api_key_fixture()
      session = Client.connect(token)

      tools = Client.list_tools(token, session)

      assert %{
               "description" => description,
               "inputSchema" => schema,
               "annotations" => annotations
             } =
               Enum.find(tools, &(&1["name"] == "get_event"))

      assert description =~ "event"
      assert schema["required"] == ["id"]
      assert annotations["readOnlyHint"] == true
    end
  end

  describe "the key a tool sees" do
    test "is the key of the current request when a session opened with another key is reused" do
      %{token: first_token} = api_key_fixture(name: "first")
      %{token: second_token} = api_key_fixture(name: "second")
      session = Client.connect(first_token)
      event = event_fixture()

      # The call log is written inside the tool from `frame.assigns.current_key`.
      assert seen_key(first_token, session, event) == "first"
      assert seen_key(second_token, session, event) == "second"
      assert seen_key(first_token, session, event) == "first"
    end

    defp seen_key(token, session, event) do
      {result, log} =
        CourierWeb.LogCapture.capture_debug_log(fn ->
          Client.call_tool(token, session, "get_event", %{id: event.id})
        end)

      assert {:ok, _event} = result
      assert [_line, name] = Regex.run(~r/mcp tool=get_event key=(\S+) status=ok/, log)
      name
    end
  end
end
