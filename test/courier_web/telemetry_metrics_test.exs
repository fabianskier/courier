defmodule CourierWeb.TelemetryMetricsTest do
  use ExUnit.Case, async: true

  @courier_events [
    [:courier, :event, :ingested],
    [:courier, :attempt, :stop],
    [:courier, :attempt, :exception],
    [:courier, :delivery, :succeeded],
    [:courier, :delivery, :failed],
    [:courier, :delivery, :retry_scheduled],
    [:courier, :endpoint, :degraded],
    [:courier, :endpoint, :recovered],
    [:courier, :queue, :lag]
  ]

  describe "Requirement: Metrics for every event" do
    test "Scenario: Metrics defined" do
      metrics = CourierWeb.Telemetry.metrics()
      event_names = MapSet.new(metrics, & &1.event_name)

      for event <- @courier_events do
        assert event in event_names, "no metric for #{inspect(event)}"
      end

      for event <- Courier.Telemetry.events() ++ [Courier.Telemetry.queue_lag_event()] do
        assert event in event_names, "no metric for #{inspect(event)}"
      end
    end

    test "the time to first attempt keeps only attempt 1" do
      metric =
        Enum.find(CourierWeb.Telemetry.metrics(), fn metric ->
          metric.name == [:courier, :attempt, :stop, :since_created_ms]
        end)

      assert %Telemetry.Metrics.Summary{measurement: :since_created_ms} = metric
      assert metric.keep.(%{number: 1})
      refute metric.keep.(%{number: 2})
    end

    test "courier metrics are tagged by outcome, status class, reason and queue" do
      tags = fn name, type ->
        CourierWeb.Telemetry.metrics()
        |> Enum.find(&(&1.name == name and &1.__struct__ == type))
        |> Map.fetch!(:tags)
      end

      assert tags.([:courier, :attempt, :stop, :duration], Telemetry.Metrics.Summary) ==
               [:outcome, :status_class]

      assert tags.([:courier, :attempt, :stop, :duration], Telemetry.Metrics.Counter) ==
               [:outcome]

      assert tags.([:courier, :delivery, :failed, :attempts], Telemetry.Metrics.Counter) ==
               [:reason]

      assert tags.([:courier, :queue, :lag, :seconds], Telemetry.Metrics.LastValue) == [:queue]
    end
  end
end
