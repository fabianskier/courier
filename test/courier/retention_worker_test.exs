defmodule Courier.Retention.WorkerTest do
  # Not async: the log scenario lowers the global log level (CourierWeb.LogCapture).
  use Courier.DataCase, async: false
  use Oban.Testing, repo: Courier.Repo

  import Ecto.Query
  import Courier.AuditFixtures
  import Courier.EventsFixtures

  alias Courier.Ingestion.Event
  alias Courier.Retention.Worker

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

  # An event received `days` ago whose deliveries completed a day later, each
  # with the given number of attempts.
  defp old_event(days, attempts_per_delivery) do
    event = event_fixture()

    Repo.update_all(from(e in Event, where: e.id == ^event.id),
      set: [inserted_at: days_ago(days)]
    )

    for attempts <- attempts_per_delivery do
      delivery =
        delivery_fixture(%{
          event_id: event.id,
          status: "succeeded",
          completed_at: days_ago(days - 1)
        })

      for number <- 1..attempts//1,
          do: attempt_fixture(%{delivery_id: delivery.id, number: number})
    end

    event
  end

  defp attach(handler_id) do
    test_pid = self()

    :telemetry.attach(
      handler_id,
      Courier.Telemetry.retention_pruned_event(),
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  describe "Requirement: Daily job and report" do
    test "Scenario: Run reported" do
      attach("retention-run-reported")

      old_event(40, [2, 2])
      old_event(40, [2, 2])
      old_event(40, [1])
      kept = old_event(10, [3])

      {result, log} =
        CourierWeb.LogCapture.capture_debug_log(fn -> perform_job(Worker, %{}) end)

      assert result == :ok

      assert_received {:telemetry, [:courier, :retention, :pruned],
                       %{events: 3, deliveries: 5, attempts: 9}, %{days: 30}}

      assert [line] =
               log |> String.split("\n") |> Enum.filter(&(&1 =~ "retention pruned"))

      assert line =~ "[info]"
      assert line =~ "events=3 deliveries=5 attempts=9 days=30"

      assert [%Event{id: id}] = Repo.all(Event)
      assert id == kept.id
    end

    test "a run that deletes nothing is reported too" do
      attach("retention-run-empty")

      {result, log} =
        CourierWeb.LogCapture.capture_debug_log(fn -> perform_job(Worker, %{}) end)

      assert result == :ok

      assert_received {:telemetry, [:courier, :retention, :pruned],
                       %{events: 0, deliveries: 0, attempts: 0}, %{days: 30}}

      assert log =~ "retention pruned events=0 deliveries=0 attempts=0 days=30"
    end

    test "Scenario: Scheduled daily" do
      config = Application.fetch_env!(:courier, Oban)

      assert config[:queues][:maintenance] == 1

      assert {Oban.Plugins.Cron, crontab: crontab} =
               List.keyfind(config[:plugins], Oban.Plugins.Cron, 0)

      assert {"30 3 * * *", Worker} in crontab
      assert Worker.new(%{}).changes.queue == "maintenance"

      # Once a day: a fixed minute and hour, every day of every month.
      assert {:ok, expression} = Oban.Cron.Expression.parse("30 3 * * *")
      assert MapSet.new(expression.minutes) == MapSet.new([30])
      assert MapSet.new(expression.hours) == MapSet.new([3])

      # Oban accepts the crontab with both jobs.
      assert :ok = config |> Keyword.delete(:testing) |> Oban.Config.validate()
    end
  end
end
