defmodule Courier.Telemetry.DeliveryTelemetryTest do
  # Not async: telemetry handlers are global, so events of other tests would arrive here.
  use Courier.DataCase, async: false
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures

  alias Courier.Delivery
  alias Courier.Delivery.Client
  alias Courier.Delivery.Worker

  setup do
    test_pid = self()
    handler_id = "delivery-telemetry-#{inspect(test_pid)}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        Courier.Telemetry.events(),
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    %{delivery: delivery_fixture()}
  end

  defp respond(status) do
    Req.Test.stub(Client, fn conn -> Plug.Conn.send_resp(conn, status, "body") end)
  end

  defp attempt(delivery), do: perform_job(Worker, %{delivery_id: delivery.id})

  defp attempt_attrs do
    %{
      started_at: DateTime.utc_now(),
      duration_ms: 5,
      url: "https://hooks.public.test/courier",
      request_headers: %{"webhook-signature" => "[redacted]"},
      response_status: 500,
      response_body: "boom"
    }
  end

  defp ids(delivery), do: %{delivery_id: delivery.id, endpoint_id: delivery.endpoint_id}

  describe "Requirement: Delivery outcome telemetry" do
    test "Scenario: Succeeded", %{delivery: delivery} do
      respond(500)
      assert {:snooze, _seconds} = attempt(delivery)
      assert_received {:telemetry, [:courier, :delivery, :retry_scheduled], _, _}

      respond(200)
      assert :ok = attempt(delivery)

      assert_received {:telemetry, [:courier, :delivery, :succeeded], measurements, metadata}
      assert %{attempts: 2, total_ms: total_ms} = measurements
      assert map_size(measurements) == 2
      assert is_integer(total_ms) and total_ms >= 0
      assert metadata == ids(delivery)

      refute_received {:telemetry, _, _, _}
    end

    test "Scenario: Failed for good", %{delivery: delivery} do
      respond(400)
      assert :ok = attempt(delivery)

      assert_received {:telemetry, [:courier, :delivery, :failed], measurements, metadata}
      assert %{attempts: 1, total_ms: total_ms} = measurements
      assert is_integer(total_ms) and total_ms >= 0
      assert metadata == Map.put(ids(delivery), :reason, :non_retryable)

      refute_received {:telemetry, _, _, _}
    end

    test "Scenario: Window ended", %{delivery: delivery} do
      assert {:ok, %{status: "failed"}} =
               Delivery.fail_without_attempt(delivery.id, DateTime.utc_now())

      assert_received {:telemetry, [:courier, :delivery, :failed], measurements, metadata}
      assert %{attempts: 0, total_ms: total_ms} = measurements
      assert is_integer(total_ms) and total_ms >= 0
      assert metadata == Map.put(ids(delivery), :reason, :window_ended)

      refute_received {:telemetry, _, _, _}
    end

    test "Scenario: Retry scheduled", %{delivery: delivery} do
      respond(500)
      assert {:snooze, seconds} = attempt(delivery)

      assert_received {:telemetry, [:courier, :delivery, :retry_scheduled], measurements,
                       metadata}

      assert measurements == %{delay_seconds: seconds}
      assert metadata == Map.put(ids(delivery), :attempt, 1)

      refute_received {:telemetry, _, _, _}
    end

    test "a retry that would pass the window fails with reason window_ended" do
      # The shortest backoff is one second, so the retry cannot fit.
      delivery = delivery_fixture(%{window_ends_at: DateTime.add(DateTime.utc_now(), 1, :second)})

      respond(500)
      assert :ok = attempt(delivery)

      assert_received {:telemetry, [:courier, :delivery, :failed], %{attempts: 1}, metadata}
      assert metadata == Map.put(ids(delivery), :reason, :window_ended)

      refute_received {:telemetry, _, _, _}
    end

    test "a stale result emits nothing", %{delivery: delivery} do
      now = DateTime.utc_now()
      assert {:ok, %{}} = Delivery.record_attempt(delivery.id, attempt_attrs(), {:failed, now})
      assert_received {:telemetry, [:courier, :delivery, :failed], _, _}

      assert {:ok, :stale} =
               Delivery.record_attempt(delivery.id, attempt_attrs(), {:succeeded, now})

      retry_at = {:retry_at, DateTime.add(now, 60, :second)}
      assert {:ok, :stale} = Delivery.record_attempt(delivery.id, attempt_attrs(), retry_at)
      assert {:ok, :stale} = Delivery.fail_without_attempt(delivery.id, now)

      refute_received {:telemetry, _, _, _}
    end
  end
end
