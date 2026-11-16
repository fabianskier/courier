defmodule CourierWeb.DeliveryResendTest do
  # Not async: the log line is captured by lowering the global log level.
  use CourierWeb.ConnCase, async: false
  use Oban.Testing, repo: Courier.Repo

  import Courier.AccessFixtures
  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures
  import CourierWeb.LogCapture
  import Ecto.Query

  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.{Queues, Worker}
  alias Courier.Endpoints
  alias Courier.Repo

  defp authed(conn, scopes, name \\ "ops") do
    %{token: token} = api_key_fixture(%{name: name, scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp assert_error(conn, status, code) do
    assert %{"error" => %{"code" => ^code, "message" => <<_::binary>>}} =
             json_response(conn, status)
  end

  # A `failed` delivery of a new endpoint.
  defp failed_delivery do
    {endpoint, _secret} = endpoint_fixture(%{retry_window_seconds: 3600})
    event = event_fixture(%{merchant_id: endpoint.merchant_id})

    delivery =
      delivery_fixture(%{
        endpoint_id: endpoint.id,
        event_id: event.id,
        status: "failed",
        completed_at: DateTime.utc_now()
      })

    %{endpoint: endpoint, event: event, delivery: delivery}
  end

  defp count(schema), do: Repo.aggregate(schema, :count)

  defp resends_of(delivery), do: Repo.all(where(DeliveryRecord, resend_of_id: ^delivery.id))

  defp assert_nothing_created do
    assert count(DeliveryRecord) == 1
    assert count(Oban.Job) == 0
  end

  describe "Requirement: Resend a terminal delivery" do
    test "Scenario: Resend a failed delivery", %{conn: conn} do
      %{endpoint: endpoint, event: event, delivery: failed} = failed_delivery()
      conn = authed(conn, ["write"])

      {conn, log} =
        capture_debug_log(fn -> post(conn, ~p"/api/v1/deliveries/#{failed.id}/resend") end)

      assert %{"data" => data} = json_response(conn, 202)

      assert %{
               "id" => id,
               "status" => "pending",
               "attempt_count" => 0,
               "next_attempt_at" => nil,
               "completed_at" => nil,
               "window_ends_at" => <<_::binary>>,
               "triggered_by" => "api_key:ops",
               "attempts" => [],
               "resends" => []
             } = data

      assert id != failed.id
      assert data["resend_of_id"] == failed.id
      assert data["event_id"] == event.id
      assert data["endpoint_id"] == endpoint.id

      stored = Repo.get!(DeliveryRecord, id)
      assert stored.status == "pending"
      assert stored.resend_of_id == failed.id
      assert stored.triggered_by == "api_key:ops"

      assert [job] = all_enqueued(worker: Worker)
      assert job.args == %{"delivery_id" => id}
      assert job.queue == Queues.name(endpoint.id)

      assert log =~ "[info]"
      assert log =~ "resend delivery=#{failed.id} new_delivery=#{id} actor=api_key:ops"
    end

    test "Scenario: Wrong scope", %{conn: conn} do
      %{delivery: failed} = failed_delivery()

      conn
      |> authed(["read"])
      |> post(~p"/api/v1/deliveries/#{failed.id}/resend")
      |> assert_error(403, "forbidden")

      assert_nothing_created()
    end
  end

  describe "Requirement: Deliveries in progress are not resent" do
    test "Scenario: Pending delivery", %{conn: conn} do
      pending = delivery_fixture()

      conn
      |> authed(["write"])
      |> post(~p"/api/v1/deliveries/#{pending.id}/resend")
      |> assert_error(409, "delivery_in_progress")

      assert_nothing_created()
    end

    test "Scenario: Double resend", %{conn: conn} do
      %{delivery: failed} = failed_delivery()
      conn = authed(conn, ["write"])

      first = post(conn, ~p"/api/v1/deliveries/#{failed.id}/resend")
      assert %{"data" => %{"id" => resend_id}} = json_response(first, 202)

      conn
      |> post(~p"/api/v1/deliveries/#{failed.id}/resend")
      |> assert_error(409, "resend_in_progress")

      assert [%DeliveryRecord{id: ^resend_id}] = resends_of(failed)
      assert count(DeliveryRecord) == 2
      assert count(Oban.Job) == 1
    end
  end

  describe "Requirement: Resends need an enabled endpoint" do
    test "Scenario: Endpoint disabled", %{conn: conn} do
      %{endpoint: endpoint, delivery: failed} = failed_delivery()
      {:ok, _endpoint} = Endpoints.update_endpoint(endpoint, %{enabled: false})

      conn
      |> authed(["write"])
      |> post(~p"/api/v1/deliveries/#{failed.id}/resend")
      |> assert_error(422, "endpoint_disabled")

      assert_nothing_created()
    end

    test "Scenario: Unknown delivery", %{conn: conn} do
      failed_delivery()
      conn = authed(conn, ["write"])

      conn
      |> post(~p"/api/v1/deliveries/#{Ecto.UUID.generate()}/resend")
      |> assert_error(404, "not_found")

      conn
      |> post(~p"/api/v1/deliveries/not-a-uuid/resend")
      |> assert_error(404, "not_found")

      assert_nothing_created()
    end
  end

  describe "Requirement: Read a delivery with its attempts" do
    test "Scenario: Resend links", %{conn: conn} do
      %{event: event, delivery: failed} = failed_delivery()

      resent = conn |> authed(["write"]) |> post(~p"/api/v1/deliveries/#{failed.id}/resend")
      assert %{"data" => %{"id" => resend_id}} = json_response(resent, 202)

      reader = authed(conn, ["read"], "reader")

      original = get(reader, ~p"/api/v1/deliveries/#{failed.id}")
      assert %{"data" => data} = json_response(original, 200)
      assert %{"resend_of_id" => nil, "triggered_by" => "system", "status" => "failed"} = data

      assert [
               %{
                 "id" => ^resend_id,
                 "status" => "pending",
                 "triggered_by" => "api_key:ops",
                 "inserted_at" => <<_::binary>>
               } = link
             ] = data["resends"]

      assert link |> Map.keys() |> Enum.sort() == ~w(id inserted_at status triggered_by)

      resend = get(reader, ~p"/api/v1/deliveries/#{resend_id}")
      assert %{"data" => data} = json_response(resend, 200)
      assert data["resend_of_id"] == failed.id
      assert %{"triggered_by" => "api_key:ops", "resends" => [], "attempts" => []} = data

      # The event's deliveries show the link too.
      shown = get(reader, ~p"/api/v1/events/#{event.id}")
      assert %{"data" => %{"deliveries" => deliveries}} = json_response(shown, 200)

      assert Map.new(deliveries, &{&1["id"], &1["resend_of_id"]}) ==
               %{failed.id => nil, resend_id => failed.id}
    end

    test "resends are listed oldest first", %{conn: conn} do
      %{delivery: failed} = failed_delivery()
      writer = authed(conn, ["write"])

      first = post(writer, ~p"/api/v1/deliveries/#{failed.id}/resend")
      assert %{"data" => %{"id" => first_id}} = json_response(first, 202)

      DeliveryRecord
      |> Repo.get!(first_id)
      |> Ecto.Changeset.change(status: "failed", completed_at: DateTime.utc_now())
      |> Repo.update!()

      second = post(writer, ~p"/api/v1/deliveries/#{failed.id}/resend")
      assert %{"data" => %{"id" => second_id}} = json_response(second, 202)

      shown = conn |> authed(["read"], "reader") |> get(~p"/api/v1/deliveries/#{failed.id}")
      assert %{"data" => %{"resends" => resends}} = json_response(shown, 200)

      assert Enum.map(resends, &{&1["id"], &1["status"]}) ==
               [{first_id, "failed"}, {second_id, "pending"}]
    end
  end
end
