defmodule CourierWeb.DeliveryReadFieldsTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures
  import Courier.MerchantsFixtures

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "Requirement: Read a delivery with its attempts" do
    test "Scenario: Delivery shows its event and creation time", %{conn: conn} do
      merchant = merchant_fixture()
      event = event_fixture(%{merchant_id: merchant.id, type: "payment.succeeded"})
      {endpoint, _secret} = endpoint_fixture(%{merchant_id: merchant.id})
      delivery = delivery_fixture(%{event_id: event.id, endpoint_id: endpoint.id})

      conn = get(authed(conn, ["read"]), ~p"/api/v1/deliveries/#{delivery.id}")

      assert %{
               "data" => %{
                 "event_type" => "payment.succeeded",
                 "merchant_id" => merchant_id,
                 "inserted_at" => inserted_at,
                 "attempts" => [],
                 "resends" => []
               }
             } = json_response(conn, 200)

      assert merchant_id == merchant.id
      assert {:ok, parsed, 0} = DateTime.from_iso8601(inserted_at)
      assert DateTime.compare(parsed, delivery.inserted_at) == :eq
    end
  end
end
