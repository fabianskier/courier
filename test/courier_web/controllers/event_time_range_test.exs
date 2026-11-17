defmodule CourierWeb.EventTimeRangeTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.EventsFixtures
  import Courier.MerchantsFixtures

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp ids(conn), do: conn |> json_response(200) |> Map.fetch!("data") |> Enum.map(& &1["id"])

  describe "Requirement: Read events" do
    test "Scenario: Events in a time range", %{conn: conn} do
      merchant = merchant_fixture()

      for hour <- [10, 12] do
        event_fixture(%{merchant_id: merchant.id, received_at: at(hour)})
      end

      eleven = event_fixture(%{merchant_id: merchant.id, received_at: at(11)})

      conn =
        get(authed(conn, ["read"]), ~p"/api/v1/events", %{
          merchant_id: merchant.id,
          since: "2026-11-10T10:30:00Z",
          until: DateTime.to_iso8601(at(12))
        })

      assert ids(conn) == [eleven.id]
    end

    test "Scenario: Invalid time range rejected", %{conn: conn} do
      conn = get(authed(conn, ["read"]), ~p"/api/v1/events", %{since: "yesterday"})

      assert %{"error" => %{"code" => "invalid", "message" => message}} = json_response(conn, 422)
      assert message =~ "since"
    end
  end

  defp at(hour), do: DateTime.new!(~D[2026-11-10], Time.new!(hour, 0, 0, {0, 6}), "Etc/UTC")
end
