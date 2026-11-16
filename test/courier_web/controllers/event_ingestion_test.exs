defmodule CourierWeb.EventIngestionTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event
  alias Courier.Merchants
  alias Courier.Repo

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp with_key(conn, key), do: put_req_header(conn, "idempotency-key", key)

  defp new_key, do: "key-#{System.unique_integer([:positive])}"

  defp body(merchant, overrides \\ %{}) do
    Map.merge(
      %{
        type: "payment.succeeded",
        merchant_id: merchant.id,
        payload: %{"amount" => 1000, "currency" => "EUR"}
      },
      overrides
    )
  end

  defp ingest(conn, key, body) do
    conn
    |> authed(["ingest"])
    |> with_key(key)
    |> post(~p"/api/v1/events", body)
  end

  defp assert_error(conn, status, code) do
    assert %{"error" => %{"code" => ^code}} = body = json_response(conn, status)
    body
  end

  defp refute_stored do
    assert Repo.aggregate(Event, :count) == 0
    assert Repo.aggregate(Delivery, :count) == 0
  end

  describe "Requirement: Accept events" do
    test "Scenario: Event accepted", %{conn: conn} do
      merchant = merchant_fixture()

      {endpoint, _secret} =
        endpoint_fixture(%{merchant_id: merchant.id, event_types: ["payment.*"]})

      occurred_at = "2026-11-01T10:00:00.000000Z"
      key = new_key()

      conn = ingest(conn, key, body(merchant, %{occurred_at: occurred_at}))

      assert %{"data" => data} = json_response(conn, 202)

      assert %{
               "id" => id,
               "type" => "payment.succeeded",
               "merchant_id" => merchant_id,
               "payload" => %{"amount" => 1000, "currency" => "EUR"},
               "occurred_at" => ^occurred_at,
               "received_at" => received_at,
               "deliveries" => [delivery]
             } = data

      assert merchant_id == merchant.id
      assert {:ok, _received_at, 0} = DateTime.from_iso8601(received_at)
      assert %{"id" => _, "status" => "pending", "window_ends_at" => window} = delivery
      assert delivery["endpoint_id"] == endpoint.id
      assert {:ok, _window, 0} = DateTime.from_iso8601(window)
      refute conn.resp_body =~ key
      assert %Event{} = Repo.get(Event, id)
    end

    test "Scenario: Wrong scope", %{conn: conn} do
      merchant = merchant_fixture()

      conn
      |> authed(["read", "write"])
      |> with_key(new_key())
      |> post(~p"/api/v1/events", body(merchant))
      |> assert_error(403, "forbidden")

      refute_stored()
    end
  end

  describe "Requirement: Idempotency key is required" do
    test "Scenario: Missing key", %{conn: conn} do
      merchant = merchant_fixture()

      body =
        conn
        |> authed(["ingest"])
        |> post(~p"/api/v1/events", body(merchant))
        |> assert_error(422, "invalid")

      assert %{"error" => %{"details" => %{"idempotency_key" => [_ | _]}}} = body
      refute_stored()
    end

    test "Scenario: Malformed key", %{conn: conn} do
      merchant = merchant_fixture()

      for key <- ["", String.duplicate("k", 256)] do
        body =
          conn
          |> recycle()
          |> ingest(key, body(merchant))
          |> assert_error(422, "invalid")

        assert %{"error" => %{"details" => %{"idempotency_key" => [_ | _]}}} = body
      end

      refute_stored()
    end
  end

  describe "Requirement: Repeats return the original event" do
    test "Scenario: Exact repeat", %{conn: conn} do
      merchant = merchant_fixture()
      endpoint_fixture(%{merchant_id: merchant.id})
      key = new_key()

      first = conn |> ingest(key, body(merchant)) |> json_response(202)
      second = build_conn() |> ingest(key, body(merchant)) |> json_response(200)

      assert second["data"]["id"] == first["data"]["id"]
      assert second["data"]["deliveries"] == first["data"]["deliveries"]
      assert Repo.aggregate(Event, :count) == 1
      assert Repo.aggregate(Delivery, :count) == 1
    end
  end

  describe "Requirement: Reused keys are rejected" do
    test "Scenario: Key reused with a different body", %{conn: conn} do
      merchant = merchant_fixture()
      key = new_key()

      %{"data" => %{"id" => id}} = conn |> ingest(key, body(merchant)) |> json_response(202)
      original = Repo.get!(Event, id)

      build_conn()
      |> ingest(key, body(merchant, %{payload: %{"amount" => 2000, "currency" => "EUR"}}))
      |> assert_error(422, "idempotency_key_reused")

      assert Repo.aggregate(Event, :count) == 1
      assert Repo.get!(Event, id) == original
    end
  end

  describe "Requirement: Disabled merchants are rejected" do
    test "Scenario: Merchant disabled", %{conn: conn} do
      merchant = merchant_fixture()
      endpoint_fixture(%{merchant_id: merchant.id})
      {:ok, merchant} = Merchants.update_merchant(merchant, %{enabled: false})

      conn
      |> ingest(new_key(), body(merchant))
      |> assert_error(422, "merchant_disabled")

      refute_stored()
    end
  end

  describe "Requirement: Payload size limit" do
    test "Scenario: Payload too large", %{conn: conn} do
      merchant = merchant_fixture()
      endpoint_fixture(%{merchant_id: merchant.id})
      payload = %{"blob" => String.duplicate("a", 300 * 1024)}

      conn
      |> ingest(new_key(), body(merchant, %{payload: payload}))
      |> assert_error(413, "payload_too_large")

      refute_stored()
    end
  end
end
