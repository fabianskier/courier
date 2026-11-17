defmodule Courier.DeliveryListFiltersTest do
  use Courier.DataCase, async: true

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Delivery
  alias Courier.Delivery.Delivery, as: DeliverySchema
  alias Courier.Ingestion.Event
  alias Courier.Repo

  defp ids(items), do: Enum.map(items, & &1.id)

  defp newest_first(deliveries) do
    deliveries
    |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id}, :desc)
    |> ids()
  end

  # A delivery for a new endpoint of the event's merchant.
  defp delivery_for(%Event{} = event, attrs \\ %{}) do
    {endpoint, _secret} = endpoint_fixture(%{merchant_id: event.merchant_id})

    attrs
    |> Map.merge(%{endpoint_id: endpoint.id, event_id: event.id})
    |> delivery_fixture()
  end

  defp set_inserted_at(delivery, %DateTime{} = at) do
    {1, _} =
      DeliverySchema
      |> where(id: ^delivery.id)
      |> Repo.update_all(set: [inserted_at: at])

    %{delivery | inserted_at: at}
  end

  describe "Requirement: Filter deliveries" do
    test "Scenario: Filtered by merchant" do
      event = event_fixture()
      mine = for _ <- 1..2, do: delivery_for(event)
      _other = delivery_fixture()

      assert {:ok, %{items: items, next_cursor: nil}} =
               Delivery.list_deliveries(%{merchant_id: event.merchant_id})

      assert ids(items) == newest_first(mine)
    end

    test "Scenario: Filtered by event type" do
      refund = event_fixture(%{type: "refund.created"})
      refunded = delivery_for(refund)
      _payment = delivery_for(event_fixture(%{type: "payment.succeeded"}))

      assert {:ok, %{items: items, next_cursor: nil}} =
               Delivery.list_deliveries(%{event_type: "refund.created"})

      assert ids(items) == [refunded.id]
    end

    test "Scenario: Event type matches exactly" do
      _refunded = delivery_for(event_fixture(%{type: "refund.created"}))

      assert {:ok, %{items: [], next_cursor: nil}} =
               Delivery.list_deliveries(%{event_type: "refund"})
    end

    test "Scenario: Since is inclusive" do
      at = ~U[2026-11-10 12:00:00.000000Z]
      before = delivery_fixture() |> set_inserted_at(DateTime.add(at, -1, :microsecond))
      exact = delivery_fixture() |> set_inserted_at(at)
      later = delivery_fixture() |> set_inserted_at(DateTime.add(at, 1, :second))

      assert {:ok, %{items: items, next_cursor: nil}} = Delivery.list_deliveries(%{since: at})

      assert ids(items) == newest_first([exact, later])
      refute before.id in ids(items)
    end

    test "Scenario: Until is exclusive" do
      at = ~U[2026-11-10 12:00:00.000000Z]
      earlier = delivery_fixture() |> set_inserted_at(DateTime.add(at, -1, :second))
      just_before = delivery_fixture() |> set_inserted_at(DateTime.add(at, -1, :microsecond))
      _exact = delivery_fixture() |> set_inserted_at(at)

      assert {:ok, %{items: items, next_cursor: nil}} = Delivery.list_deliveries(%{until: at})

      assert ids(items) == newest_first([earlier, just_before])
    end

    test "Scenario: Deliveries in a time range" do
      since = ~U[2026-11-10 12:00:00.000000Z]
      until = ~U[2026-11-10 13:00:00.000000Z]
      _before = delivery_fixture() |> set_inserted_at(DateTime.add(since, -1, :second))
      first = delivery_fixture() |> set_inserted_at(since)
      middle = delivery_fixture() |> set_inserted_at(DateTime.add(since, 30, :minute))
      _at_until = delivery_fixture() |> set_inserted_at(until)

      assert {:ok, %{items: items, next_cursor: nil}} =
               Delivery.list_deliveries(%{since: since, until: until})

      assert ids(items) == newest_first([first, middle])
    end

    test "Scenario: Filters combined" do
      since = ~U[2026-11-10 12:00:00.000000Z]
      refund = event_fixture(%{type: "refund.created"})
      payment = event_fixture(%{merchant_id: refund.merchant_id, type: "payment.succeeded"})

      match =
        refund |> delivery_for(%{status: "failed"}) |> set_inserted_at(since)

      _wrong_status = refund |> delivery_for() |> set_inserted_at(since)
      _wrong_type = payment |> delivery_for(%{status: "failed"}) |> set_inserted_at(since)

      _too_early =
        refund
        |> delivery_for(%{status: "failed"})
        |> set_inserted_at(DateTime.add(since, -1, :second))

      _other_merchant =
        event_fixture(%{type: "refund.created"})
        |> delivery_for(%{status: "failed"})
        |> set_inserted_at(since)

      assert {:ok, %{items: items, next_cursor: nil}} =
               Delivery.list_deliveries(%{
                 status: "failed",
                 merchant_id: refund.merchant_id,
                 event_type: "refund.created",
                 since: since,
                 until: DateTime.add(since, 1, :hour)
               })

      assert ids(items) == [match.id]
    end

    test "Scenario: New filters combined with endpoint and event" do
      event = event_fixture()
      match = delivery_for(event)
      _other_endpoint = delivery_for(event)

      assert {:ok, %{items: items, next_cursor: nil}} =
               Delivery.list_deliveries(%{
                 merchant_id: event.merchant_id,
                 event_type: event.type,
                 endpoint_id: match.endpoint_id,
                 event_id: event.id
               })

      assert ids(items) == [match.id]
    end

    test "Scenario: Malformed id matches nothing" do
      _delivery = delivery_fixture()

      assert {:ok, %{items: [], next_cursor: nil}} =
               Delivery.list_deliveries(%{merchant_id: "not-a-uuid"})
    end

    test "Scenario: Unknown merchant matches nothing" do
      _delivery = delivery_fixture()

      assert {:ok, %{items: [], next_cursor: nil}} =
               Delivery.list_deliveries(%{merchant_id: Ecto.UUID.generate()})
    end

    test "Scenario: Nil filters are not applied" do
      delivery = delivery_fixture()

      assert {:ok, %{items: items}} =
               Delivery.list_deliveries(%{
                 merchant_id: nil,
                 event_type: nil,
                 since: nil,
                 until: nil
               })

      assert delivery.id in ids(items)
    end
  end

  describe "Requirement: List deliveries" do
    test "Scenario: Listed deliveries carry their event" do
      event = event_fixture(%{type: "refund.created"})
      delivery = delivery_for(event)

      assert {:ok, %{items: [listed]}} = Delivery.list_deliveries(%{event_id: event.id})

      assert listed.id == delivery.id
      assert %Event{id: event_id, type: "refund.created", merchant_id: merchant_id} = listed.event
      assert event_id == event.id
      assert merchant_id == event.merchant_id
    end

    test "Scenario: Pages follow the cursor with filters" do
      event = event_fixture()
      mine = for _ <- 1..3, do: delivery_for(event)
      _other = delivery_fixture()
      expected = newest_first(mine)

      assert {:ok, %{items: page1, next_cursor: cursor}} =
               Delivery.list_deliveries(%{merchant_id: event.merchant_id, limit: 2})

      assert is_binary(cursor)

      assert {:ok, %{items: page2, next_cursor: nil}} =
               Delivery.list_deliveries(%{
                 merchant_id: event.merchant_id,
                 limit: 2,
                 cursor: cursor
               })

      assert ids(page1 ++ page2) == expected
    end

    test "Scenario: Existing MCP options unchanged" do
      {endpoint, _secret} = endpoint_fixture()
      failed = delivery_fixture(%{endpoint_id: endpoint.id, status: "failed"})
      _pending = delivery_fixture(%{endpoint_id: endpoint.id})
      _elsewhere = delivery_fixture(%{status: "failed"})

      assert {:ok, %{items: [listed], next_cursor: nil}} =
               Delivery.list_deliveries(%{
                 status: "failed",
                 endpoint_id: endpoint.id,
                 event_id: failed.event_id,
                 limit: 20,
                 cursor: nil
               })

      assert listed.id == failed.id
      assert %Event{} = listed.event

      assert {:ok, %{items: []}} = Delivery.list_deliveries(%{status: "exploded"})
      assert {:error, :invalid_cursor} = Delivery.list_deliveries(%{cursor: "made-up"})
    end
  end

  describe "Requirement: Read a delivery with its attempts" do
    test "Scenario: Delivery shows its event and creation time" do
      event = event_fixture(%{type: "refund.created"})
      delivery = delivery_for(event)

      assert {:ok, read} = Delivery.get_delivery(delivery.id)

      assert %Event{type: "refund.created"} = read.event
      assert read.event.id == event.id
      assert read.event.merchant_id == event.merchant_id
      assert %DateTime{} = read.inserted_at
      assert is_list(read.attempts)
      assert is_list(read.resends)
    end
  end
end
