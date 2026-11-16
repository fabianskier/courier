defmodule Courier.Telemetry.AttemptTelemetryTest do
  # Not async: telemetry handlers are global, so events of other tests would arrive here.
  use Courier.DataCase, async: false
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Delivery.Client
  alias Courier.Delivery.Worker

  @payload_marker "payload-marker-7f3a"
  @response_marker "response-marker-9c1d"

  setup do
    test_pid = self()
    handler_id = "attempt-telemetry-#{inspect(test_pid)}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        Courier.Telemetry.attempt_events(),
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {endpoint, secret} = endpoint_fixture()

    event =
      event_fixture(%{merchant_id: endpoint.merchant_id, payload: %{"note" => @payload_marker}})

    delivery = delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})

    %{delivery: delivery, secret: secret}
  end

  defp attempt(delivery), do: perform_job(Worker, %{delivery_id: delivery.id})

  defp start_metadata(delivery, number) do
    %{delivery_id: delivery.id, endpoint_id: delivery.endpoint_id, number: number}
  end

  # The span adds its own context reference; everything else is ours.
  defp own(metadata), do: Map.delete(metadata, :telemetry_span_context)

  describe "Requirement: Attempt telemetry" do
    test "Scenario: Attempt start and stop", %{delivery: delivery} do
      test_pid = self()

      Req.Test.stub(Client, fn conn ->
        # The start event must already be there when the request arrives.
        send(test_pid, :request_received)
        Plug.Conn.send_resp(conn, 503, @response_marker)
      end)

      assert {:snooze, _seconds} = attempt(delivery)

      assert_received {:telemetry, [:courier, :attempt, :start], start_measurements, start_meta}
      assert_received :request_received
      assert is_integer(start_measurements.system_time)
      assert own(start_meta) == start_metadata(delivery, 1)

      assert_received {:telemetry, [:courier, :attempt, :stop], measurements, metadata}
      assert is_integer(measurements.duration) and measurements.duration >= 0
      assert is_integer(measurements.since_created_ms) and measurements.since_created_ms >= 0

      assert own(metadata) ==
               Map.merge(start_metadata(delivery, 1), %{
                 outcome: :retry,
                 status: 503,
                 status_class: "5xx"
               })

      refute_received {:telemetry, _, _, _}
    end

    test "the start event is emitted before the request", %{delivery: delivery} do
      test_pid = self()

      Req.Test.stub(Client, fn conn ->
        send(test_pid, :request_received)
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      assert :ok = attempt(delivery)

      assert {:messages, messages} = Process.info(self(), :messages)

      order =
        Enum.flat_map(messages, fn
          {:telemetry, [:courier, :attempt, name], _, _} -> [name]
          :request_received -> [:request]
          _other -> []
        end)

      assert order == [:start, :request, :stop]
    end

    test "Scenario: Network error", %{delivery: delivery} do
      Req.Test.stub(Client, &Req.Test.transport_error(&1, :timeout))

      assert {:snooze, _seconds} = attempt(delivery)

      assert_received {:telemetry, [:courier, :attempt, :start], _, _}
      assert_received {:telemetry, [:courier, :attempt, :stop], measurements, metadata}
      assert is_integer(measurements.duration)

      assert own(metadata) ==
               Map.merge(start_metadata(delivery, 1), %{
                 outcome: :retry,
                 status: nil,
                 status_class: "error"
               })

      refute_received {:telemetry, _, _, _}
    end

    test "the second attempt has number 2 and a success has class 2xx", %{delivery: delivery} do
      Req.Test.stub(Client, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
      assert {:snooze, _seconds} = attempt(delivery)
      assert_received {:telemetry, [:courier, :attempt, :stop], _, %{number: 1}}

      Req.Test.stub(Client, fn conn -> Plug.Conn.send_resp(conn, 204, "") end)
      assert :ok = attempt(delivery)

      assert_received {:telemetry, [:courier, :attempt, :stop], _, metadata}
      assert %{number: 2, outcome: :success, status: 204, status_class: "2xx"} = metadata
    end

    test "a non-retryable response has outcome give_up", %{delivery: delivery} do
      Req.Test.stub(Client, fn conn -> Plug.Conn.send_resp(conn, 400, "no") end)
      assert :ok = attempt(delivery)

      assert_received {:telemetry, [:courier, :attempt, :stop], _, metadata}
      assert %{outcome: :give_up, status: 400, status_class: "4xx"} = metadata
    end

    test "no metadata value contains the payload, the response body or the signature",
         %{delivery: delivery, secret: secret} do
      test_pid = self()

      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:sent, body, Plug.Conn.get_req_header(conn, "webhook-signature")})
        Plug.Conn.send_resp(conn, 503, @response_marker)
      end)

      assert {:snooze, _seconds} = attempt(delivery)

      assert_received {:sent, body, [signature_header]}
      assert body =~ @payload_marker
      signatures = for "v1," <> signature <- String.split(signature_header, " "), do: signature
      assert signatures != []

      forbidden =
        [@payload_marker, @response_marker, body, signature_header, secret] ++ signatures

      assert_received {:telemetry, [:courier, :attempt, :start], start_measurements, start_meta}
      assert_received {:telemetry, [:courier, :attempt, :stop], stop_measurements, stop_meta}

      for map <- [start_measurements, start_meta, stop_measurements, stop_meta] do
        printed = inspect(map, limit: :infinity, printable_limit: :infinity)
        for text <- forbidden, do: refute(printed =~ text)
      end

      assert stop_meta |> own() |> Map.keys() |> Enum.sort() ==
               [:delivery_id, :endpoint_id, :number, :outcome, :status, :status_class]
    end
  end
end
