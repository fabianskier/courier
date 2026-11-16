defmodule Courier.Telemetry.QueueLagTest do
  # Not async: telemetry handlers are global, so events of other tests would arrive here.
  use Courier.DataCase, async: false

  alias Courier.Delivery.QueueLag
  alias Courier.Delivery.Queues
  alias Courier.Delivery.Worker

  @lag [:courier, :queue, :lag]

  setup do
    test_pid = self()
    handler_id = "queue-lag-telemetry-#{inspect(test_pid)}"

    :ok =
      :telemetry.attach(
        handler_id,
        Courier.Telemetry.queue_lag_event(),
        fn event, measurements, metadata, _config ->
          # Handlers run in the emitting process: keep only this test's own
          # calls, not a tick of the application's poller.
          if self() == test_pid, do: send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  # A job that became runnable `seconds_ago`. Oban inserts a job with
  # `scheduled_at` as `scheduled` and nothing stages jobs in tests, so the job
  # is made `available` the way Oban's stager does: keeping its `scheduled_at`.
  defp available_job(queue, seconds_ago) do
    scheduled_at = DateTime.add(DateTime.utc_now(), -seconds_ago, :second)
    job = insert_job(queue, scheduled_at: scheduled_at)

    {1, nil} =
      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "available"])

    job
  end

  defp insert_job(queue, opts) do
    {:ok, job} =
      %{delivery_id: Ecto.UUID.generate()}
      |> Worker.new([queue: queue] ++ opts)
      |> then(&Oban.insert(Oban, &1))

    job
  end

  describe "Requirement: Queue lag telemetry" do
    test "Scenario: Waiting jobs measured" do
      queue = Queues.name(Ecto.UUID.generate())
      other_queue = Queues.name(Ecto.UUID.generate())

      available_job(queue, 30)
      available_job(queue, 5)
      available_job(other_queue, 90)

      assert :ok = QueueLag.measure()

      assert_received {:telemetry, @lag, %{seconds: seconds, available: 2}, %{queue: ^queue}}
      assert is_float(seconds)
      assert seconds >= 30
      assert seconds < 90

      assert_received {:telemetry, @lag, %{seconds: other_seconds, available: 1},
                       %{queue: ^other_queue}}

      assert other_seconds >= 90

      # One event per queue.
      refute_received {:telemetry, @lag, _measurements, _metadata}
    end

    test "Scenario: Empty queues are silent" do
      queue = Queues.name(Ecto.UUID.generate())

      # Jobs that are not waiting for a worker: in backoff, or already done.
      insert_job(queue, schedule_in: 60)
      insert_job(queue, state: "completed")
      insert_job(queue, state: "executing")

      assert :ok = QueueLag.measure()

      refute_received {:telemetry, @lag, _measurements, _metadata}
    end

    test "a non-endpoint queue is ignored" do
      available_job("maintenance", 30)
      available_job("endpoints", 30)

      assert :ok = QueueLag.measure()

      refute_received {:telemetry, @lag, _measurements, _metadata}
    end
  end
end
