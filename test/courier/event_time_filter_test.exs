defmodule Courier.EventTimeFilterTest do
  use Courier.DataCase, async: true

  import Courier.EventsFixtures

  alias Courier.Ingestion

  @since ~U[2026-11-10 12:00:00.000000Z]
  @until ~U[2026-11-10 13:00:00.000000Z]

  defp ids(items), do: Enum.map(items, & &1.id)

  defp received(at, attrs \\ %{}), do: event_fixture(Map.put(attrs, :received_at, at))

  describe "Requirement: Read events" do
    test "Scenario: Events in a time range" do
      _before = received(DateTime.add(@since, -1, :microsecond))
      first = received(@since)
      middle = received(DateTime.add(@since, 30, :minute))
      _at_until = received(@until)

      assert {:ok, %{items: items, next_cursor: nil}} =
               Ingestion.list_events(%{limit: 50, since: @since, until: @until})

      assert MapSet.new(ids(items)) == MapSet.new([first.id, middle.id])
    end

    test "Scenario: Since is inclusive" do
      _before = received(DateTime.add(@since, -1, :microsecond))
      exact = received(@since)

      assert {:ok, %{items: items}} = Ingestion.list_events(%{limit: 50, since: @since})

      assert exact.id in ids(items)
      assert length(items) == 1
    end

    test "Scenario: Until is exclusive" do
      just_before = received(DateTime.add(@until, -1, :microsecond))
      _exact = received(@until)

      assert {:ok, %{items: items}} = Ingestion.list_events(%{limit: 50, until: @until})

      assert ids(items) == [just_before.id]
    end

    test "Scenario: Time range combined with merchant and type" do
      match = received(@since, %{type: "refund.created"})
      _other_type = received(@since, %{merchant_id: match.merchant_id})
      _other_merchant = received(@since, %{type: "refund.created"})
      _too_late = received(@until, %{merchant_id: match.merchant_id, type: "refund.created"})

      assert {:ok, %{items: items, next_cursor: nil}} =
               Ingestion.list_events(%{
                 limit: 50,
                 merchant_id: match.merchant_id,
                 type: "refund.created",
                 since: @since,
                 until: @until
               })

      assert ids(items) == [match.id]
    end

    test "Scenario: Nil bounds are not applied" do
      event = received(@since)

      assert {:ok, %{items: items}} =
               Ingestion.list_events(%{limit: 50, since: nil, until: nil})

      assert event.id in ids(items)
    end
  end
end
