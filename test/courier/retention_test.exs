defmodule Courier.RetentionTest do
  # Not async: the boot scenario sets COURIER_RETENTION_DAYS in the OS
  # environment while it evaluates config/runtime.exs.
  use CourierWeb.ConnCase, async: false

  import Ecto.Query
  import Courier.AccessFixtures
  import Courier.AuditFixtures
  import Courier.EventsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event
  alias Courier.Repo
  alias Courier.Retention

  @now ~U[2026-11-17 12:00:00.000000Z]

  defp days_ago(days), do: DateTime.add(@now, -days, :day)

  defp received(days) do
    event = event_fixture(%{received_at: days_ago(days)})
    backdate_event(event.id, days)
    event
  end

  defp backdate_event(event_id, days) do
    at = days_ago(days)
    Repo.update_all(from(e in Event, where: e.id == ^event_id), set: [inserted_at: at])
  end

  defp delivery(event, status, attrs \\ %{}) do
    completed_at = Map.get(attrs, :completed_days_ago)

    attrs =
      attrs
      |> Map.delete(:completed_days_ago)
      |> Map.merge(%{event_id: event.id, status: status})
      |> Map.put(:completed_at, completed_at && days_ago(completed_at))

    d = delivery_fixture(attrs)
    attempt_fixture(%{delivery_id: d.id, number: 1})
    if status != "pending", do: attempt_fixture(%{delivery_id: d.id, number: 2})
    d
  end

  defp counts do
    %{
      events: Repo.aggregate(Event, :count),
      deliveries: Repo.aggregate(Delivery, :count),
      attempts: Repo.aggregate(Attempt, :count)
    }
  end

  defp read_runtime_config(value) do
    previous = System.get_env("COURIER_RETENTION_DAYS")

    try do
      if value,
        do: System.put_env("COURIER_RETENTION_DAYS", value),
        else: System.delete_env("COURIER_RETENTION_DAYS")

      "config/runtime.exs"
      |> Config.Reader.read!(env: :test)
      |> get_in([:courier, :retention_days])
    after
      if previous,
        do: System.put_env("COURIER_RETENTION_DAYS", previous),
        else: System.delete_env("COURIER_RETENTION_DAYS")
    end
  end

  describe "Requirement: Retention period" do
    test "Scenario: Default period" do
      assert Retention.parse_days(nil) == 30
      assert read_runtime_config(nil) == 30
    end

    test "Scenario: Configured period" do
      assert Retention.parse_days("7") == 7
      assert read_runtime_config("7") == 7
    end

    test "Scenario: Invalid period rejected" do
      for value <- ["1", "soon", "0", "-5", "7.5", "7 days"] do
        assert_raise ArgumentError, ~r/COURIER_RETENTION_DAYS/, fn ->
          Retention.parse_days(value)
        end
      end

      for value <- ["1", "soon"] do
        assert_raise ArgumentError, ~r/COURIER_RETENTION_DAYS/, fn ->
          read_runtime_config(value)
        end
      end

      assert Retention.parse_days("2") == 2
    end
  end

  describe "Requirement: Old finished events are pruned" do
    test "Scenario: Old finished event pruned" do
      event = received(40)
      delivery(event, "succeeded", %{completed_days_ago: 39})
      delivery(event, "failed", %{completed_days_ago: 39})

      assert %{events: 1, deliveries: 2, attempts: 4, batches: 1} =
               Retention.prune(30, now: @now)

      assert counts() == %{events: 0, deliveries: 0, attempts: 0}
    end

    test "Scenario: Pending delivery keeps the event" do
      event = received(40)
      delivery(event, "succeeded", %{completed_days_ago: 39})
      delivery(event, "pending")

      assert %{events: 0, deliveries: 0, attempts: 0, batches: 0} =
               Retention.prune(30, now: @now)

      assert counts() == %{events: 1, deliveries: 2, attempts: 3}
    end

    test "Scenario: Recent resend keeps an old event" do
      event = received(40)
      original = delivery(event, "failed", %{completed_days_ago: 39})

      delivery(event, "succeeded", %{
        completed_days_ago: 1,
        endpoint_id: original.endpoint_id,
        resend_of_id: original.id,
        triggered_by: "api"
      })

      assert %{events: 0, batches: 0} = Retention.prune(30, now: @now)
      assert counts() == %{events: 1, deliveries: 2, attempts: 4}
    end

    test "Scenario: Event with resends pruned together" do
      event = received(40)
      original = delivery(event, "failed", %{completed_days_ago: 35})

      delivery(event, "succeeded", %{
        completed_days_ago: 35,
        endpoint_id: original.endpoint_id,
        resend_of_id: original.id,
        triggered_by: "api"
      })

      recent = received(10)
      delivery(recent, "succeeded", %{completed_days_ago: 10})

      assert %{events: 1, deliveries: 2, attempts: 4, batches: 1} =
               Retention.prune(30, now: @now)

      assert counts() == %{events: 1, deliveries: 1, attempts: 2}
      assert Repo.get(Event, recent.id)
      refute Repo.get(Event, event.id)
    end
  end

  describe "Requirement: Deletion respects append-only attempts" do
    test "Scenario: Batched pruning" do
      merchant = merchant_fixture()
      at = days_ago(40)

      rows =
        for i <- 1..2_500 do
          %{
            id: Ecto.UUID.generate(),
            merchant_id: merchant.id,
            idempotency_key: "batch-#{i}",
            request_hash: :crypto.strong_rand_bytes(32),
            type: "payment.succeeded",
            payload: %{"n" => i},
            occurred_at: at,
            received_at: at,
            inserted_at: at,
            updated_at: at
          }
        end

      rows |> Enum.chunk_every(500) |> Enum.each(&Repo.insert_all(Event, &1))

      handler_id = "retention-batches-#{System.unique_integer()}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:courier, :repo, :query],
        fn _event, _measurements, %{query: query}, _ ->
          if query =~ ~r/^DELETE FROM "events"/, do: send(test_pid, {:events_deleted, query})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert %{events: 2_500, batches: 3} = Retention.prune(30, now: @now)
      assert Repo.aggregate(Event, :count) == 0

      for _ <- 1..3, do: assert_received({:events_deleted, _})
      refute_received {:events_deleted, _}
    end

    test "Scenario: Delete outside the job rejected" do
      event = received(40)
      delivery(event, "succeeded", %{completed_days_ago: 39})
      kept = received(1)
      delivery(kept, "succeeded", %{completed_days_ago: 1})

      # A prune run earlier in the same transaction does not leave the
      # exception switched on.
      assert %{events: 1} = Retention.prune(30, now: @now)

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.transaction(fn -> Repo.delete_all(Attempt) end)
      end

      assert Repo.aggregate(Attempt, :count) == 2
    end
  end

  describe "Requirement: Idempotency keys after pruning" do
    test "Scenario: Key reused after pruning", %{conn: conn} do
      merchant = merchant_fixture()
      old = event_fixture(%{merchant_id: merchant.id, idempotency_key: "order-42"})
      backdate_event(old.id, 40)

      assert %{events: 1} = Retention.prune(30, now: @now)

      %{token: token} = api_key_fixture(%{scopes: ["ingest"]})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("idempotency-key", "order-42")
        |> post(~p"/api/v1/events", %{
          type: "payment.succeeded",
          merchant_id: merchant.id,
          payload: %{"amount" => 1000}
        })

      assert json_response(conn, 202)
      assert [new] = Repo.all(from e in Event, where: e.idempotency_key == "order-42")
      assert new.id != old.id
    end
  end
end
