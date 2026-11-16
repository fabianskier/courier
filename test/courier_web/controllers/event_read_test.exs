defmodule CourierWeb.EventReadTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures
  import Courier.MerchantsFixtures
  import Ecto.Query

  alias Courier.Ingestion
  alias Courier.Ingestion.Event
  alias Courier.Repo

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp assert_error(conn, status, code) do
    assert %{"error" => %{"code" => ^code}} = json_response(conn, status)
  end

  # Stores an event created `seconds_ago` seconds ago, so ordering is deterministic.
  defp event_at(attrs, seconds_ago) do
    event = event_fixture(attrs)
    inserted_at = DateTime.add(DateTime.utc_now(), -seconds_ago, :second)
    Repo.update_all(from(e in Event, where: e.id == ^event.id), set: [inserted_at: inserted_at])
    event
  end

  defp ids(conn), do: conn |> json_response(200) |> Map.fetch!("data") |> Enum.map(& &1["id"])

  describe "Requirement: Read events" do
    test "Scenario: List and filter events", %{conn: conn} do
      merchant = merchant_fixture()
      other = merchant_fixture()

      older = event_at(%{merchant_id: merchant.id}, 30)
      newer = event_at(%{merchant_id: merchant.id}, 10)
      _refund = event_at(%{merchant_id: merchant.id, type: "refund.created"}, 20)
      _other_merchant = event_at(%{merchant_id: other.id}, 5)

      conn =
        get(authed(conn, ["read"]), ~p"/api/v1/events", %{
          merchant_id: merchant.id,
          type: "payment.succeeded"
        })

      assert %{"data" => [first | _], "next_cursor" => nil} = json_response(conn, 200)
      assert ids(conn) == [newer.id, older.id]

      assert %{"type" => "payment.succeeded", "merchant_id" => merchant_id, "payload" => _} =
               first

      assert merchant_id == merchant.id
      refute Map.has_key?(first, "idempotency_key")
      refute Map.has_key?(first, "request_hash")
    end

    test "Scenario: Show an event with its deliveries", %{conn: conn} do
      merchant = merchant_fixture()

      {payments, _} = endpoint_fixture(%{merchant_id: merchant.id, event_types: ["payment.*"]})
      {refunds, _} = endpoint_fixture(%{merchant_id: merchant.id, event_types: ["refund.*"]})

      {:ok, :created, event} =
        Ingestion.ingest(
          %{type: "payment.succeeded", merchant_id: merchant.id, payload: %{"amount" => 1}},
          "key-#{System.unique_integer([:positive])}"
        )

      conn = get(authed(conn, ["read"]), ~p"/api/v1/events/#{event.id}")

      assert %{"data" => data} = json_response(conn, 200)

      assert %{
               "id" => id,
               "type" => "payment.succeeded",
               "payload" => %{"amount" => 1},
               "deliveries" => deliveries
             } = data

      assert id == event.id
      refute conn.resp_body =~ event.idempotency_key

      statuses = Map.new(deliveries, &{&1["endpoint_id"], &1["status"]})
      assert statuses == %{payments.id => "pending", refunds.id => "skipped"}
      assert Enum.all?(deliveries, &match?(%{"id" => <<_::binary>>}, &1))
    end

    test "Scenario: Unknown event", %{conn: conn} do
      conn = authed(conn, ["read"])

      conn
      |> get(~p"/api/v1/events/#{Ecto.UUID.generate()}")
      |> assert_error(404, "not_found")

      conn
      |> get(~p"/api/v1/events/not-a-uuid")
      |> assert_error(404, "not_found")
    end

    test "events are listed newest first across pages", %{conn: conn} do
      merchant = merchant_fixture()
      expected = for age <- [50, 40, 30, 20, 10], do: event_at(%{merchant_id: merchant.id}, age)
      expected = expected |> Enum.reverse() |> Enum.map(& &1.id)
      conn = authed(conn, ["read"])

      page1 = get(conn, ~p"/api/v1/events", %{limit: 2})
      assert %{"next_cursor" => cursor1} = json_response(page1, 200)
      page2 = get(conn, ~p"/api/v1/events", %{limit: 2, cursor: cursor1})
      assert %{"next_cursor" => cursor2} = json_response(page2, 200)
      page3 = get(conn, ~p"/api/v1/events", %{limit: 2, cursor: cursor2})
      assert %{"next_cursor" => nil} = json_response(page3, 200)

      assert ids(page1) ++ ids(page2) ++ ids(page3) == expected
    end

    test "a malformed merchant_id gives an empty page", %{conn: conn} do
      event_fixture()

      conn = get(authed(conn, ["read"]), ~p"/api/v1/events", %{merchant_id: "nope"})
      assert %{"data" => [], "next_cursor" => nil} = json_response(conn, 200)
    end

    test "reading needs the read scope", %{conn: conn} do
      event = event_fixture()
      conn = authed(conn, ["ingest", "write"])

      conn |> get(~p"/api/v1/events") |> assert_error(403, "forbidden")
      conn |> get(~p"/api/v1/events/#{event.id}") |> assert_error(403, "forbidden")
    end
  end
end
