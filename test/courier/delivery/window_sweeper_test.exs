defmodule Courier.Delivery.WindowSweeperTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.Queues
  alias Courier.Delivery.WindowSweeper
  alias Courier.Delivery.Worker
  alias Courier.Endpoints

  setup do
    {endpoint, _secret} = endpoint_fixture()
    %{endpoint: endpoint}
  end

  defp past(seconds \\ 60), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  # A delivery with its job, as ingestion stores them. One event per
  # delivery: a delivery is unique per event and endpoint.
  defp delivery_with_job(endpoint, attrs) do
    event = event_fixture(%{merchant_id: endpoint.merchant_id})

    delivery =
      delivery_fixture(Map.merge(%{endpoint_id: endpoint.id, event_id: event.id}, Map.new(attrs)))

    {:ok, job} =
      %{delivery_id: delivery.id}
      |> Worker.new(queue: Queues.name(endpoint.id))
      |> Oban.insert()

    {delivery, job}
  end

  defp reload(%DeliveryRecord{id: id}), do: Repo.get!(DeliveryRecord, id)
  defp reload(%Oban.Job{id: id}), do: Repo.get!(Oban.Job, id)

  defp attempt_count(delivery) do
    Repo.aggregate(from(a in Attempt, where: a.delivery_id == ^delivery.id), :count)
  end

  describe "Requirement: Expired pending deliveries are swept" do
    test "Scenario: Delivery of a disabled endpoint expires", %{endpoint: endpoint} do
      {delivery, job} = delivery_with_job(endpoint, %{window_ends_at: past()})
      {:ok, _endpoint} = Endpoints.update_endpoint(endpoint, %{"enabled" => false})

      assert :ok = perform_job(WindowSweeper, %{})

      stored = reload(delivery)
      assert stored.status == "failed"
      assert %DateTime{} = stored.completed_at
      assert stored.next_attempt_at == nil
      assert stored.attempt_count == 0
      assert attempt_count(delivery) == 0

      assert reload(job).state == "cancelled"
      refute_enqueued(worker: WindowSweeper)
    end

    test "Scenario: Pending delivery inside its window is kept", %{endpoint: endpoint} do
      {delivery, job} = delivery_with_job(endpoint, %{})

      assert :ok = perform_job(WindowSweeper, %{})

      stored = reload(delivery)
      assert stored.status == "pending"
      assert stored.completed_at == nil
      assert stored.updated_at == delivery.updated_at

      assert reload(job).state == "available"
      refute_enqueued(worker: WindowSweeper)
    end

    test "already terminal deliveries are untouched", %{endpoint: endpoint} do
      completed_at = past(3600)

      deliveries =
        for status <- ~w(succeeded failed skipped) do
          {delivery, _job} =
            delivery_with_job(endpoint, %{
              status: status,
              window_ends_at: past(),
              completed_at: completed_at
            })

          delivery
        end

      assert :ok = perform_job(WindowSweeper, %{})

      for delivery <- deliveries do
        stored = reload(delivery)
        assert stored.status == delivery.status
        assert stored.completed_at == completed_at
        assert stored.updated_at == delivery.updated_at
      end

      # Their jobs are not cancelled either.
      assert length(all_enqueued(worker: Worker)) == 3
    end

    test "a full batch re-enqueues the sweeper, oldest deliveries first", %{endpoint: endpoint} do
      {newest, newest_job} = delivery_with_job(endpoint, %{window_ends_at: past(10)})
      {oldest, oldest_job} = delivery_with_job(endpoint, %{window_ends_at: past(300)})
      {middle, middle_job} = delivery_with_job(endpoint, %{window_ends_at: past(100)})

      assert :ok = perform_job(WindowSweeper, %{batch_size: 2})

      assert reload(oldest).status == "failed"
      assert reload(middle).status == "failed"
      assert reload(newest).status == "pending"
      assert reload(oldest_job).state == "cancelled"
      assert reload(middle_job).state == "cancelled"
      assert reload(newest_job).state == "available"

      # The next run keeps the batch size and finishes the work.
      assert [%Oban.Job{args: %{"batch_size" => 2}, queue: "maintenance"} = next] =
               all_enqueued(worker: WindowSweeper)

      assert :ok = perform_job(WindowSweeper, next.args)

      assert reload(newest).status == "failed"
      assert reload(newest_job).state == "cancelled"
    end
  end

  test "the sweeper is scheduled every 5 minutes in the maintenance queue" do
    config = Application.fetch_env!(:courier, Oban)

    assert config[:queues][:maintenance] == 1

    assert {Oban.Plugins.Cron, crontab: [{"*/5 * * * *", WindowSweeper}]} in config[:plugins]
  end
end
