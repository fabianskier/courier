defmodule CourierMCP.CallLogTest do
  # The MCP session runs in its own process: the sandbox must be shared, and
  # `capture_debug_log/1` changes the global log level.
  use CourierWeb.ConnCase, async: false

  import Courier.AccessFixtures
  import Courier.AuditFixtures
  import Courier.EventsFixtures

  alias CourierMCP.Client
  alias CourierWeb.LogCapture

  defp call_logged(token, session, tool, arguments) do
    {result, log} =
      LogCapture.capture_debug_log(fn -> Client.call_tool(token, session, tool, arguments) end)

    lines =
      log
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "mcp tool="))

    {result, lines}
  end

  describe "Requirement: Log every tool call" do
    test "Scenario: Call logged" do
      %{token: token} = api_key_fixture(name: "agent", scopes: ["read"])
      session = Client.connect(token)
      delivery = delivery_fixture(%{status: "failed"})

      {result, lines} = call_logged(token, session, "get_delivery", %{id: delivery.id})

      assert {:ok, _data} = result
      assert [line] = lines
      assert line =~ "[info]"
      assert line =~ "tool=get_delivery"
      assert line =~ "key=agent"
      assert line =~ "status=ok"
      assert line =~ ~r/duration_ms=\d+/
      assert line =~ delivery.id
    end

    test "Scenario: Failed call logged" do
      %{token: token} = api_key_fixture(name: "reader", scopes: ["read"])
      session = Client.connect(token)
      delivery = delivery_fixture(%{status: "failed"})

      {result, lines} = call_logged(token, session, "resend_delivery", %{id: delivery.id})

      assert {:error, %{"error" => %{"code" => "forbidden"}}} = result
      assert [line] = lines
      assert line =~ "[info]"
      assert line =~ "tool=resend_delivery"
      assert line =~ "key=reader"
      assert line =~ "status=error:forbidden"
      assert line =~ delivery.id
    end

    test "Scenario: Log without secrets" do
      %{token: token} = api_key_fixture(name: "agent", scopes: ["read"])
      session = Client.connect(token)
      memo = "payload-marker-#{System.unique_integer([:positive])}"
      event = event_fixture(payload: %{"memo" => memo, "amount" => 4242})

      {result, lines} = call_logged(token, session, "get_event", %{id: event.id})

      assert {:ok, %{"payload" => %{"untrusted_data" => data}}} = result
      assert data =~ memo
      assert [line] = lines
      assert line =~ "tool=get_event"
      assert line =~ event.id
      refute line =~ token
      refute line =~ memo
      refute line =~ "4242"
      refute line =~ "untrusted_data"
    end

    test "a call for an unknown event is logged once with its error code" do
      %{token: token} = api_key_fixture(name: "agent", scopes: ["read"])
      session = Client.connect(token)

      {result, lines} =
        call_logged(token, session, "get_event", %{id: Ecto.UUID.generate()})

      assert {:error, %{"error" => %{"code" => "not_found"}}} = result
      assert [line] = lines
      assert line =~ "status=error:not_found"
    end
  end
end
