defmodule Courier.Delivery.ResendTest do
  # Not async: "Simultaneous resends" runs resends from two processes in the
  # sandbox's shared mode.
  use Courier.DataCase, async: false
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Audit
  alias Courier.Delivery
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.{Queues, Worker}
  alias Courier.Endpoints

  @actor "api_key:ops"

  # A terminal delivery (`failed` unless `status` is given) of a new endpoint.
  defp terminal_delivery(attrs \\ %{}) do
    {endpoint, _secret} = endpoint_fixture(%{retry_window_seconds: 3600})
    event = event_fixture(%{merchant_id: endpoint.merchant_id})

    delivery =
      %{
        endpoint_id: endpoint.id,
        event_id: event.id,
        status: "failed",
        completed_at: DateTime.utc_now()
      }
      |> Map.merge(Map.new(attrs))
      |> delivery_fixture()

    %{endpoint: endpoint, event: event, delivery: delivery}
  end

  defp finish(%DeliveryRecord{} = delivery, status) do
    delivery
    |> Ecto.Changeset.change(status: status, completed_at: DateTime.utc_now())
    |> Repo.update!()
  end

  defp count(schema), do: Repo.aggregate(schema, :count)

  defp resends_of(delivery), do: Repo.all(where(DeliveryRecord, resend_of_id: ^delivery.id))

  describe "Requirement: Resend a terminal delivery" do
    test "Scenario: Resend a failed delivery" do
      %{endpoint: endpoint, event: event, delivery: failed} = terminal_delivery()
      before = DateTime.utc_now()

      assert {:ok, %DeliveryRecord{} = resend} = Delivery.resend(failed.id, @actor)

      assert resend.id != failed.id
      assert resend.status == "pending"
      assert resend.resend_of_id == failed.id
      assert resend.triggered_by == @actor
      assert resend.event_id == event.id
      assert resend.endpoint_id == endpoint.id
      assert resend.attempt_count == 0
      assert resend.completed_at == nil
      assert_in_delta DateTime.diff(resend.window_ends_at, before, :second), 3600, 5

      stored = Repo.get!(DeliveryRecord, resend.id)
      assert stored.resend_of_id == failed.id
      assert stored.triggered_by == @actor
      assert stored.window_ends_at == resend.window_ends_at

      assert [job] = all_enqueued(worker: Worker)
      assert job.args == %{"delivery_id" => resend.id}
      assert job.queue == Queues.name(endpoint.id)
    end

    test "Scenario: Original unchanged" do
      %{delivery: delivery} = terminal_delivery()
      attempt_fixture(%{delivery_id: delivery.id, number: 1, response_status: 500})
      attempt_fixture(%{delivery_id: delivery.id, number: 2, response_status: 500})

      {1, _} =
        Repo.update_all(where(DeliveryRecord, id: ^delivery.id), set: [attempt_count: 2])

      original = Repo.get!(DeliveryRecord, delivery.id)
      attempts = Audit.list_attempts(delivery.id)
      assert length(attempts) == 2

      assert {:ok, resend} = Delivery.resend(delivery.id, @actor)

      assert Repo.get!(DeliveryRecord, delivery.id) == original
      assert original.status == "failed"
      assert original.attempt_count == 2
      assert Audit.list_attempts(delivery.id) == attempts
      assert Audit.list_attempts(resend.id) == []
    end

    test "Scenario: Resend a skipped delivery" do
      %{endpoint: endpoint, delivery: skipped} =
        terminal_delivery(%{status: "skipped", window_ends_at: nil})

      assert {:ok, resend} = Delivery.resend(skipped.id, @actor)

      assert resend.status == "pending"
      assert resend.endpoint_id == endpoint.id
      assert resend.resend_of_id == skipped.id
      assert %DateTime{} = resend.window_ends_at
      assert_enqueued(worker: Worker, args: %{"delivery_id" => resend.id})
    end

    test "Scenario: Resend a resend" do
      %{delivery: failed} = terminal_delivery()
      assert {:ok, first} = Delivery.resend(failed.id, @actor)
      finish(first, "succeeded")

      assert {:ok, second} = Delivery.resend(first.id, "api_key:other")

      assert second.resend_of_id == first.id
      assert second.triggered_by == "api_key:other"
      assert second.event_id == failed.event_id
      assert second.endpoint_id == failed.endpoint_id
      assert Repo.get!(DeliveryRecord, first.id).resend_of_id == failed.id
    end
  end

  describe "Requirement: Deliveries in progress are not resent" do
    test "Scenario: Pending delivery" do
      pending = delivery_fixture()

      assert {:error, :delivery_in_progress} = Delivery.resend(pending.id, @actor)

      assert count(DeliveryRecord) == 1
      assert count(Oban.Job) == 0
    end

    test "Scenario: Double resend" do
      %{delivery: failed} = terminal_delivery()

      assert {:ok, resend} = Delivery.resend(failed.id, @actor)
      assert {:error, :resend_in_progress} = Delivery.resend(failed.id, @actor)

      assert [%DeliveryRecord{id: id}] = resends_of(failed)
      assert id == resend.id
      assert count(Oban.Job) == 1

      # Once the first resend is finished, the delivery can be resent again.
      finish(resend, "failed")
      assert {:ok, again} = Delivery.resend(failed.id, @actor)
      assert again.resend_of_id == failed.id
      assert length(resends_of(failed)) == 2
    end

    test "Scenario: Simultaneous resends" do
      %{delivery: failed} = terminal_delivery()

      results =
        1..2
        |> Task.async_stream(fn _ -> Delivery.resend(failed.id, @actor) end, timeout: :infinity)
        |> Enum.map(fn {:ok, result} -> result end)

      assert [{:ok, resend}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert Enum.count(results, &(&1 == {:error, :resend_in_progress})) == 1
      assert [%DeliveryRecord{id: id}] = resends_of(failed)
      assert id == resend.id
      assert count(Oban.Job) == 1
    end
  end

  describe "Requirement: Resends need an enabled endpoint" do
    test "Scenario: Endpoint disabled" do
      %{endpoint: endpoint, delivery: failed} = terminal_delivery()
      {:ok, _endpoint} = Endpoints.update_endpoint(endpoint, %{enabled: false})

      assert {:error, :endpoint_disabled} = Delivery.resend(failed.id, @actor)

      assert count(DeliveryRecord) == 1
      assert count(Oban.Job) == 0
    end

    test "Scenario: Unknown delivery" do
      terminal_delivery()

      assert {:error, :not_found} = Delivery.resend(Ecto.UUID.generate(), @actor)
      assert {:error, :not_found} = Delivery.resend("not-a-uuid", @actor)
      assert {:error, :not_found} = Delivery.resend(nil, @actor)

      assert count(DeliveryRecord) == 1
      assert count(Oban.Job) == 0
    end
  end
end
