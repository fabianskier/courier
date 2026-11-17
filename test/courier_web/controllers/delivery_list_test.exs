defmodule CourierWeb.DeliveryListTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures
  import Courier.MerchantsFixtures
  import Ecto.Query

  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event
  alias Courier.Repo

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp assert_error(conn, status, code) do
    assert %{"error" => %{"code" => ^code}} = json_response(conn, status)
  end

  defp ids(conn), do: conn |> json_response(200) |> Map.fetch!("data") |> Enum.map(& &1["id"])

  defp set_inserted_at(%Delivery{} = delivery, %DateTime{} = at) do
    {1, _} =
      Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: [inserted_at: at])

    %{delivery | inserted_at: at}
  end

  # A delivery of `event` to a new endpoint of the event's merchant, created `seconds_ago`.
  defp delivery_for(%Event{} = event, attrs \\ %{}, seconds_ago \\ 0) do
    {endpoint, _secret} = endpoint_fixture(%{merchant_id: event.merchant_id})

    attrs
    |> Map.merge(%{endpoint_id: endpoint.id, event_id: event.id})
    |> delivery_fixture()
    |> set_inserted_at(DateTime.add(DateTime.utc_now(), -seconds_ago, :second))
  end

  describe "Requirement: List deliveries" do
    test "Scenario: Newest deliveries first", %{conn: conn} do
      merchant = merchant_fixture()
      event = event_fixture(%{merchant_id: merchant.id, type: "payment.succeeded"})
      older = delivery_for(event, %{}, 30)
      middle = delivery_for(event, %{}, 20)
      newer = delivery_for(event, %{}, 10)

      conn = authed(conn, ["read"])
      first = get(conn, ~p"/api/v1/deliveries", %{limit: "2"})

      assert %{"data" => [item, _], "next_cursor" => <<_::binary>>} = json_response(first, 200)
      assert ids(first) == [newer.id, middle.id]

      merchant_id = merchant.id
      event_id = event.id
      endpoint_id = newer.endpoint_id

      assert %{
               "event_id" => ^event_id,
               "event_type" => "payment.succeeded",
               "merchant_id" => ^merchant_id,
               "endpoint_id" => ^endpoint_id,
               "status" => "pending",
               "attempt_count" => 0,
               "next_attempt_at" => _,
               "completed_at" => nil,
               "resend_of_id" => nil,
               "triggered_by" => "system",
               "inserted_at" => <<_::binary>>
             } = item

      refute Map.has_key?(item, "attempts")

      all = get(conn, ~p"/api/v1/deliveries")
      assert %{"next_cursor" => nil} = json_response(all, 200)
      assert ids(all) == [newer.id, middle.id, older.id]
    end

    test "Scenario: Pages follow the cursor", %{conn: conn} do
      event = event_fixture()
      oldest = delivery_for(event, %{}, 30)
      middle = delivery_for(event, %{}, 20)
      newest = delivery_for(event, %{}, 10)

      conn = authed(conn, ["read"])
      first = get(conn, ~p"/api/v1/deliveries", %{limit: "2"})
      assert %{"next_cursor" => cursor} = json_response(first, 200)
      assert ids(first) == [newest.id, middle.id]

      second = get(conn, ~p"/api/v1/deliveries", %{limit: "2", cursor: cursor})
      assert %{"next_cursor" => nil} = json_response(second, 200)
      assert ids(second) == [oldest.id]
    end

    test "Scenario: Listing needs the read scope", %{conn: conn} do
      conn = get(authed(conn, ["ingest"]), ~p"/api/v1/deliveries")
      assert_error(conn, 403, "forbidden")
    end
  end

  describe "Requirement: Filter deliveries" do
    test "Scenario: Filters combined", %{conn: conn} do
      merchant = merchant_fixture()
      payment = event_fixture(%{merchant_id: merchant.id, type: "payment.succeeded"})
      refund = event_fixture(%{merchant_id: merchant.id, type: "refund.created"})
      other = event_fixture(%{type: "payment.succeeded"})

      match = delivery_for(payment, %{status: "failed"})
      _pending = delivery_for(payment, %{status: "pending"})
      _refund = delivery_for(refund, %{status: "failed"})
      _other_merchant = delivery_for(other, %{status: "failed"})

      conn =
        get(authed(conn, ["read"]), ~p"/api/v1/deliveries", %{
          status: "failed",
          merchant_id: merchant.id,
          event_type: "payment.succeeded"
        })

      assert ids(conn) == [match.id]
    end

    test "Scenario: Filter by endpoint and event", %{conn: conn} do
      event = event_fixture()
      by_endpoint = delivery_for(event)
      by_event = delivery_fixture()

      conn = authed(conn, ["read"])

      endpoint_list = get(conn, ~p"/api/v1/deliveries", %{endpoint_id: by_endpoint.endpoint_id})
      assert ids(endpoint_list) == [by_endpoint.id]

      event_list = get(conn, ~p"/api/v1/deliveries", %{event_id: by_event.event_id})
      assert ids(event_list) == [by_event.id]
    end

    test "Scenario: Deliveries in a time range", %{conn: conn} do
      event = event_fixture()
      at_10 = ~U[2026-11-10 10:00:00.000000Z]
      at_11 = ~U[2026-11-10 11:00:00.000000Z]
      at_12 = ~U[2026-11-10 12:00:00.000000Z]

      _ten = event |> delivery_for() |> set_inserted_at(at_10)
      eleven = event |> delivery_for() |> set_inserted_at(at_11)
      _twelve = event |> delivery_for() |> set_inserted_at(at_12)

      conn =
        get(authed(conn, ["read"]), ~p"/api/v1/deliveries", %{
          since: "2026-11-10T10:30:00Z",
          until: DateTime.to_iso8601(at_12)
        })

      assert ids(conn) == [eleven.id]
    end

    test "Scenario: Invalid filter rejected", %{conn: conn} do
      conn = authed(conn, ["read"])

      lost = get(conn, ~p"/api/v1/deliveries", %{status: "lost"})
      assert %{"error" => %{"code" => "invalid", "message" => message}} = json_response(lost, 422)
      assert message =~ "status"

      tomorrow = get(conn, ~p"/api/v1/deliveries", %{until: "tomorrow"})

      assert %{"error" => %{"code" => "invalid", "message" => message}} =
               json_response(tomorrow, 422)

      assert message =~ "until"

      assert_error(
        get(conn, ~p"/api/v1/deliveries", %{since: "2026-11-10T10:30:00"}),
        422,
        "invalid"
      )

      assert_error(get(conn, ~p"/api/v1/deliveries", %{limit: "0"}), 422, "invalid")
      assert_error(get(conn, ~p"/api/v1/deliveries", %{cursor: "garbage"}), 422, "invalid")
    end

    test "Scenario: Malformed id matches nothing", %{conn: conn} do
      _delivery = delivery_fixture()

      conn = get(authed(conn, ["read"]), ~p"/api/v1/deliveries", %{endpoint_id: "not-a-uuid"})

      assert %{"data" => [], "next_cursor" => nil} = json_response(conn, 200)
    end
  end
end
