defmodule CourierMCP.EndpointHealthTest do
  # The MCP session runs in its own process: the sandbox must be shared.
  use CourierWeb.ConnCase, async: false

  import Courier.AccessFixtures
  import Courier.AuditFixtures
  import Courier.EndpointsFixtures

  alias Courier.Repo
  alias CourierMCP.Client

  setup do
    %{token: token} = api_key_fixture()
    %{token: token, session: Client.connect(token)}
  end

  describe "Requirement: Get endpoint health" do
    test "Scenario: Degraded endpoint", %{token: token, session: session} do
      {endpoint, secret} = endpoint_fixture()
      degraded_at = ~U[2026-11-16 10:00:00.000000Z]

      endpoint
      |> Ecto.Changeset.change(consecutive_failures: 23, degraded_at: degraded_at)
      |> Repo.update!()

      for _ <- 1..2, do: delivery_fixture(%{endpoint_id: endpoint.id, status: "failed"})
      _pending = delivery_fixture(%{endpoint_id: endpoint.id})
      _other = delivery_fixture(%{status: "failed"})

      assert {:ok, result} =
               Client.call_tool(token, session, "get_endpoint_health", %{id: endpoint.id})

      assert %{
               "enabled" => true,
               "consecutive_failures" => 23,
               "degraded" => true,
               "deliveries_by_status" => %{
                 "pending" => 1,
                 "succeeded" => 0,
                 "failed" => 2,
                 "skipped" => 0
               }
             } = result

      assert result["id"] == endpoint.id
      assert {:ok, ^degraded_at, 0} = DateTime.from_iso8601(result["degraded_at"])

      encoded = Jason.encode!(result)
      refute encoded =~ "whsec_"
      refute encoded =~ secret
    end

    test "a healthy endpoint is not degraded", %{token: token, session: session} do
      {endpoint, _secret} = endpoint_fixture()

      assert {:ok, %{"degraded" => false, "degraded_at" => nil, "consecutive_failures" => 0}} =
               Client.call_tool(token, session, "get_endpoint_health", %{id: endpoint.id})
    end

    test "Scenario: Unknown endpoint", %{token: token, session: session} do
      assert {:error, %{"error" => %{"code" => "not_found", "message" => message}}} =
               Client.call_tool(token, session, "get_endpoint_health", %{
                 id: Ecto.UUID.generate()
               })

      assert message =~ "endpoint"

      assert {:error, %{"error" => %{"code" => "not_found"}}} =
               Client.call_tool(token, session, "get_endpoint_health", %{id: "not-a-uuid"})
    end
  end
end
