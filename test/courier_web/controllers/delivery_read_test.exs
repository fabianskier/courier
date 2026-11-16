defmodule CourierWeb.DeliveryReadTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.AuditFixtures

  alias Courier.Delivery

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp assert_error(conn, status, code) do
    assert %{"error" => %{"code" => ^code}} = json_response(conn, status)
  end

  defp attempt_attrs(started_at, status, body, error \\ nil) do
    %{
      started_at: started_at,
      duration_ms: 25,
      url: "https://hooks.public.test/courier",
      request_headers: %{
        "content-type" => "application/json",
        "webhook-id" => "evt",
        "webhook-signature" => "[redacted]"
      },
      response_status: status,
      response_body: body,
      error: error
    }
  end

  describe "Requirement: Read a delivery with its attempts" do
    test "Scenario: Delivery with attempts", %{conn: conn} do
      delivery = delivery_fixture()
      first_at = DateTime.add(DateTime.utc_now(), -60, :second)
      retry_at = DateTime.add(first_at, 30, :second)
      now = DateTime.utc_now()

      {:ok, _} =
        Delivery.record_attempt(
          delivery.id,
          attempt_attrs(first_at, 503, "unavailable"),
          {:retry_at, retry_at}
        )

      {:ok, _} =
        Delivery.record_attempt(delivery.id, attempt_attrs(now, 200, "ok"), {:succeeded, now})

      conn = get(authed(conn, ["read"]), ~p"/api/v1/deliveries/#{delivery.id}")

      assert %{"data" => data} = json_response(conn, 200)

      assert %{
               "id" => id,
               "event_id" => event_id,
               "endpoint_id" => endpoint_id,
               "status" => "succeeded",
               "attempt_count" => 2,
               "next_attempt_at" => nil,
               "window_ends_at" => <<_::binary>>,
               "completed_at" => <<_::binary>>,
               "attempts" => [first, second]
             } = data

      assert {id, event_id, endpoint_id} ==
               {delivery.id, delivery.event_id, delivery.endpoint_id}

      assert %{
               "number" => 1,
               "response_status" => 503,
               "response_body" => "unavailable",
               "duration_ms" => 25,
               "url" => "https://hooks.public.test/courier",
               "error" => nil,
               "started_at" => <<_::binary>>
             } = first

      assert %{"number" => 2, "response_status" => 200} = second

      refute Map.has_key?(first, "request_headers")
      refute conn.resp_body =~ "request_headers"
      refute conn.resp_body =~ "webhook-signature"
      refute conn.resp_body =~ "v1,"
      refute conn.resp_body =~ "[redacted]"
    end

    test "Scenario: Unknown delivery", %{conn: conn} do
      conn = authed(conn, ["read"])

      conn
      |> get(~p"/api/v1/deliveries/#{Ecto.UUID.generate()}")
      |> assert_error(404, "not_found")

      conn
      |> get(~p"/api/v1/deliveries/not-a-uuid")
      |> assert_error(404, "not_found")
    end

    test "reading a delivery needs the read scope", %{conn: conn} do
      delivery = delivery_fixture()

      conn
      |> authed(["ingest", "write"])
      |> get(~p"/api/v1/deliveries/#{delivery.id}")
      |> assert_error(403, "forbidden")
    end
  end
end
