defmodule Courier.Delivery.EndpointHealthTest do
  # Not async: the degraded threshold is global application config.
  use Courier.DataCase, async: false
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Delivery
  alias Courier.Delivery.Client
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.Worker
  alias Courier.Endpoints.Endpoint

  @events [[:courier, :endpoint, :degraded], [:courier, :endpoint, :recovered]]

  setup do
    previous = Application.fetch_env(:courier, :degraded_threshold)
    Application.put_env(:courier, :degraded_threshold, 3)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:courier, :degraded_threshold, value)
        :error -> Application.delete_env(:courier, :degraded_threshold)
      end
    end)

    test_pid = self()
    handler_id = "endpoint-health-#{inspect(test_pid)}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        @events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {endpoint, _secret} = endpoint_fixture()
    %{endpoint: endpoint}
  end

  # One event per delivery: a delivery is unique per event and endpoint.
  defp new_delivery(%{endpoint: endpoint}) do
    event = event_fixture(%{merchant_id: endpoint.merchant_id})
    delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})
  end

  defp attempt_attrs(overrides) do
    Map.merge(
      %{
        started_at: DateTime.utc_now(),
        duration_ms: 5,
        url: "https://hooks.public.test/courier",
        request_headers: %{"webhook-signature" => "[redacted]"}
      },
      overrides
    )
  end

  defp failed(500), do: attempt_attrs(%{response_status: 500, response_body: "boom"})
  defp failed(:timeout), do: attempt_attrs(%{error: "timeout"})
  defp failed(400), do: attempt_attrs(%{response_status: 400, response_body: "bad"})

  defp ok_attrs, do: attempt_attrs(%{response_status: 200, response_body: "ok"})

  defp retry_at, do: {:retry_at, DateTime.add(DateTime.utc_now(), 60, :second)}
  defp now, do: DateTime.utc_now()

  defp reload(%Endpoint{id: id}), do: Repo.get!(Endpoint, id)

  # Fails `n` attempts on one pending delivery.
  defp fail_times(delivery, n) do
    for _ <- 1..n do
      assert {:ok, _} = Delivery.record_attempt(delivery.id, failed(500), retry_at())
    end
  end

  describe "Requirement: Consecutive failures are counted" do
    test "Scenario: Failures counted and reset", %{endpoint: endpoint} = ctx do
      delivery = new_delivery(ctx)

      {:ok, _} = Delivery.record_attempt(delivery.id, failed(500), retry_at())
      assert reload(endpoint).consecutive_failures == 1

      {:ok, _} = Delivery.record_attempt(delivery.id, failed(:timeout), retry_at())
      assert reload(endpoint).consecutive_failures == 2

      # A 400 that is not retried ends the delivery; the next one succeeds.
      {:ok, _} = Delivery.record_attempt(delivery.id, failed(400), {:failed, now()})
      assert reload(endpoint).consecutive_failures == 3

      other = new_delivery(ctx)
      {:ok, _} = Delivery.record_attempt(other.id, ok_attrs(), {:succeeded, now()})

      stored = reload(endpoint)
      assert stored.consecutive_failures == 0
      assert stored.degraded_at == nil
    end

    test "Scenario: No attempt, no count", %{endpoint: endpoint} = ctx do
      delivery = new_delivery(ctx)
      {:ok, _} = Delivery.record_attempt(delivery.id, failed(500), retry_at())
      assert reload(endpoint).consecutive_failures == 1

      assert {:ok, %DeliveryRecord{status: "failed"}} =
               Delivery.fail_without_attempt(delivery.id, now())

      assert reload(endpoint).consecutive_failures == 1
    end

    test "a stale result changes nothing", %{endpoint: endpoint} = ctx do
      delivery = new_delivery(ctx)
      {:ok, _} = Delivery.record_attempt(delivery.id, failed(500), {:failed, now()})
      assert reload(endpoint).consecutive_failures == 1

      assert {:ok, :stale} = Delivery.record_attempt(delivery.id, failed(500), retry_at())
      assert reload(endpoint).consecutive_failures == 1
    end
  end

  describe "Requirement: Degraded endpoints" do
    test "Scenario: Endpoint becomes degraded", %{endpoint: endpoint} = ctx do
      delivery = new_delivery(ctx)
      fail_times(delivery, 2)

      assert reload(endpoint).degraded_at == nil
      refute_received {:telemetry, _, _, _}

      assert {:ok, %{health: :degraded}} =
               Delivery.record_attempt(delivery.id, failed(500), retry_at())

      stored = reload(endpoint)
      assert stored.consecutive_failures == 3
      assert %DateTime{} = stored.degraded_at

      endpoint_id = endpoint.id
      merchant_id = endpoint.merchant_id

      assert_received {:telemetry, [:courier, :endpoint, :degraded], %{consecutive_failures: 3},
                       %{endpoint_id: ^endpoint_id, merchant_id: ^merchant_id}}

      refute_received {:telemetry, _, _, _}
    end

    test "Scenario: Further failures emit no new event", %{endpoint: endpoint} = ctx do
      delivery = new_delivery(ctx)
      fail_times(delivery, 3)
      assert_received {:telemetry, [:courier, :endpoint, :degraded], _, _}
      degraded_at = reload(endpoint).degraded_at

      assert {:ok, %{health: nil}} =
               Delivery.record_attempt(delivery.id, failed(:timeout), retry_at())

      stored = reload(endpoint)
      assert stored.consecutive_failures == 4
      assert stored.degraded_at == degraded_at
      refute_received {:telemetry, _, _, _}
    end

    test "Scenario: Endpoint recovers", %{endpoint: endpoint} = ctx do
      delivery = new_delivery(ctx)
      fail_times(delivery, 3)
      assert_received {:telemetry, [:courier, :endpoint, :degraded], _, _}

      assert {:ok, %{health: :recovered}} =
               Delivery.record_attempt(delivery.id, ok_attrs(), {:succeeded, now()})

      stored = reload(endpoint)
      assert stored.consecutive_failures == 0
      assert stored.degraded_at == nil

      endpoint_id = endpoint.id

      assert_received {:telemetry, [:courier, :endpoint, :recovered], measurements,
                       %{endpoint_id: ^endpoint_id}}

      assert measurements == %{}
      refute_received {:telemetry, _, _, _}

      # A later success on a healthy endpoint emits nothing.
      other = new_delivery(ctx)

      assert {:ok, %{health: nil}} =
               Delivery.record_attempt(other.id, ok_attrs(), {:succeeded, now()})

      refute_received {:telemetry, _, _, _}
    end

    test "Scenario: Degraded endpoint still retried", %{endpoint: endpoint} = ctx do
      fail_times(new_delivery(ctx), 3)
      assert %DateTime{} = reload(endpoint).degraded_at

      delivery = new_delivery(ctx)
      test_pid = self()

      Req.Test.stub(Client, fn conn ->
        send(test_pid, :request)
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      assert {:snooze, seconds} = perform_job(Worker, %{delivery_id: delivery.id})
      assert is_integer(seconds) and seconds > 0
      assert_received :request

      stored = Repo.get!(DeliveryRecord, delivery.id)
      assert stored.status == "pending"
      assert %DateTime{} = stored.next_attempt_at
      assert stored.attempt_count == 1

      health = reload(endpoint)
      assert health.consecutive_failures == 4
      assert %DateTime{} = health.degraded_at
    end
  end

  test "the threshold must be a positive integer" do
    Application.put_env(:courier, :degraded_threshold, 0)
    assert_raise ArgumentError, fn -> Delivery.degraded_threshold() end

    Application.put_env(:courier, :degraded_threshold, 3)
    assert Delivery.degraded_threshold() == 3
  end
end
