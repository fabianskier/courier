defmodule Courier.ApplicationOrderTest do
  use ExUnit.Case, async: true

  describe "Requirement: Delivery dependencies outlive delivery jobs" do
    test "Scenario: Supervision order" do
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

      assert index.(Courier.Finch) < index.(Oban)
      assert index.(Courier.Delivery.TaskSupervisor) < index.(Oban)
      assert index.(Oban) < index.(Courier.Delivery.QueueManager)
    end
  end
end
