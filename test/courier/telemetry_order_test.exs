defmodule Courier.TelemetryOrderTest do
  use ExUnit.Case, async: true

  describe "Requirement: Queue lag measured with the database up" do
    test "Scenario: Telemetry starts after the repo" do
      # which_children/1 lists children in reverse start order.
      ids =
        Courier.Supervisor
        |> Supervisor.which_children()
        |> Enum.reverse()
        |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

      index = fn id ->
        position = Enum.find_index(ids, &(&1 == id))
        assert position, "#{inspect(id)} is not a child of Courier.Supervisor"
        position
      end

      assert index.(Courier.Repo) < index.(CourierWeb.Telemetry)
    end
  end
end
