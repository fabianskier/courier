defmodule CourierDemo.LoadStatsTest do
  use ExUnit.Case, async: true

  alias CourierDemo.Load
  alias CourierDemo.Load.Stats

  doctest Stats

  describe "Requirement: Ingestion report" do
    test "Scenario: Percentiles" do
      latencies = Enum.shuffle(Enum.to_list(1..100))

      assert Stats.percentile(latencies, 50) == 50
      assert Stats.percentile(latencies, 95) == 95
      assert Stats.percentile(latencies, 99) == 99

      tally = %{new: 100, repeats: 0, rejected: %{}, failed: 0, elapsed_ms: 2000}

      assert [_summary, "  latency p50 50 ms, p95 95 ms, p99 99 ms"] =
               Load.ingestion_report(Map.put(tally, :latencies_ms, latencies))
    end

    test "Scenario: Percentiles of an empty list are reported as n/a" do
      assert Stats.percentile([], 50) == nil
      assert Stats.format_ms(nil) == "n/a"
      assert Stats.percentile([7], 1) == 7
      assert Stats.rate(100, 2000) == 50.0
      assert Stats.rate(3, 0) == nil
      assert Stats.format_rate(50.0) == "50.0/s"
    end
  end
end
