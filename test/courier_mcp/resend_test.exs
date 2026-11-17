defmodule CourierMCP.ResendTest do
  # The MCP session runs in its own process: the sandbox must be shared.
  use CourierWeb.ConnCase, async: false

  import Courier.AccessFixtures
  import Courier.AuditFixtures
  import Ecto.Query

  alias Courier.Delivery.Delivery
  alias Courier.Repo
  alias CourierMCP.Client

  @read_tools ~w(get_event get_delivery list_deliveries list_failed_deliveries get_endpoint_health)

  defp resends_of(delivery) do
    Repo.all(from d in Delivery, where: d.resend_of_id == ^delivery.id)
  end

  describe "Requirement: Resend a delivery" do
    test "Scenario: Resent with a write key" do
      %{token: token} = api_key_fixture(name: "agent", scopes: ["read", "write"])
      session = Client.connect(token)
      failed = delivery_fixture(%{status: "failed"})

      assert {:ok, result} =
               Client.call_tool(token, session, "resend_delivery", %{id: failed.id})

      assert [resend] = resends_of(failed)
      assert resend.status == "pending"
      assert resend.triggered_by == "api_key:agent"
      assert resend.event_id == failed.event_id
      assert resend.endpoint_id == failed.endpoint_id

      assert result["resend_of_id"] == failed.id

      assert %{"status" => "pending", "triggered_by" => "api_key:agent"} =
               result["delivery"]

      assert result["delivery"]["id"] == resend.id
      assert result["delivery"]["resend_of_id"] == failed.id
    end

    test "Scenario: Read key refused" do
      %{token: token} = api_key_fixture(name: "reader", scopes: ["read"])
      session = Client.connect(token)
      failed = delivery_fixture(%{status: "failed"})

      assert {:error, %{"error" => %{"code" => "forbidden", "message" => message}}} =
               Client.call_tool(token, session, "resend_delivery", %{id: failed.id})

      assert message =~ "write"
      assert resends_of(failed) == []
    end

    test "Scenario: Pending delivery refused" do
      %{token: token} = api_key_fixture(scopes: ["read", "write"])
      session = Client.connect(token)
      pending = delivery_fixture()

      assert {:error, %{"error" => %{"code" => "delivery_in_progress"}}} =
               Client.call_tool(token, session, "resend_delivery", %{id: pending.id})

      assert resends_of(pending) == []
    end

    test "an unknown delivery is not found" do
      %{token: token} = api_key_fixture(scopes: ["read", "write"])
      session = Client.connect(token)

      assert {:error, %{"error" => %{"code" => "not_found"}}} =
               Client.call_tool(token, session, "resend_delivery", %{id: Ecto.UUID.generate()})
    end

    test "a delivery with a pending resend is refused" do
      %{token: token} = api_key_fixture(scopes: ["read", "write"])
      session = Client.connect(token)
      failed = delivery_fixture(%{status: "failed"})

      _pending_resend =
        delivery_fixture(%{
          endpoint_id: failed.endpoint_id,
          event_id: failed.event_id,
          resend_of_id: failed.id
        })

      assert {:error, %{"error" => %{"code" => "resend_in_progress"}}} =
               Client.call_tool(token, session, "resend_delivery", %{id: failed.id})
    end
  end

  describe "Requirement: Tool list" do
    test "Scenario: Tools listed" do
      %{token: token} = api_key_fixture(scopes: ["read"])
      session = Client.connect(token)

      tools = Client.list_tools(token, session)

      assert tools |> Enum.map(& &1["name"]) |> Enum.sort() ==
               Enum.sort(["resend_delivery" | @read_tools])

      for tool <- tools do
        assert is_binary(tool["description"]) and tool["description"] != ""
        assert %{"type" => "object"} = tool["inputSchema"]
      end

      for name <- @read_tools do
        tool = Enum.find(tools, &(&1["name"] == name))
        assert tool["annotations"]["readOnlyHint"] == true, "#{name} is not read-only"
      end

      resend = Enum.find(tools, &(&1["name"] == "resend_delivery"))
      assert String.starts_with?(resend["description"], "Changes state:")
      assert resend["annotations"]["readOnlyHint"] == false
      assert resend["annotations"]["destructiveHint"] == false
      assert resend["inputSchema"]["required"] == ["id"]
    end
  end
end
