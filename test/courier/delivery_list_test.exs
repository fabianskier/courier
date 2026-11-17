defmodule Courier.DeliveryListTest do
  use Courier.DataCase, async: true

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures

  alias Courier.Delivery

  defp ids(items), do: Enum.map(items, & &1.id)

  defp newest_first(deliveries) do
    deliveries
    |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id}, :desc)
    |> ids()
  end

  describe "Requirement: List deliveries" do
    test "Scenario: Filtered by status" do
      failed = delivery_fixture(%{status: "failed"})
      _pending = delivery_fixture()
      _succeeded = delivery_fixture(%{status: "succeeded"})

      assert {:ok, %{items: items, next_cursor: nil}} =
               Delivery.list_deliveries(%{status: "failed"})

      assert ids(items) == [failed.id]
    end

    test "Scenario: Filtered by endpoint" do
      {endpoint, _secret} = endpoint_fixture()
      mine = for _ <- 1..2, do: delivery_fixture(%{endpoint_id: endpoint.id})
      _other = delivery_fixture()

      assert {:ok, %{items: items, next_cursor: nil}} =
               Delivery.list_deliveries(%{endpoint_id: endpoint.id})

      assert ids(items) == newest_first(mine)
    end

    test "Scenario: Filtered by event" do
      original = delivery_fixture(%{status: "failed"})

      resend =
        delivery_fixture(%{
          endpoint_id: original.endpoint_id,
          event_id: original.event_id,
          resend_of_id: original.id
        })

      _other = delivery_fixture()

      assert {:ok, %{items: items, next_cursor: nil}} =
               Delivery.list_deliveries(%{event_id: original.event_id})

      assert ids(items) == newest_first([original, resend])
    end

    test "Scenario: Filters combined" do
      {endpoint, _secret} = endpoint_fixture()
      failed = delivery_fixture(%{endpoint_id: endpoint.id, status: "failed"})
      _pending = delivery_fixture(%{endpoint_id: endpoint.id})
      _other_failed = delivery_fixture(%{status: "failed"})

      assert {:ok, %{items: items}} =
               Delivery.list_deliveries(%{status: "failed", endpoint_id: endpoint.id})

      assert ids(items) == [failed.id]
    end

    test "Scenario: A filter id that is not a UUID matches nothing" do
      delivery_fixture()

      assert {:ok, %{items: [], next_cursor: nil}} =
               Delivery.list_deliveries(%{endpoint_id: "not-a-uuid"})

      assert {:ok, %{items: [], next_cursor: nil}} =
               Delivery.list_deliveries(%{event_id: "not-a-uuid"})
    end

    test "Scenario: Newest first without attempts" do
      deliveries = for _ <- 1..3, do: delivery_fixture()
      attempt_fixture(%{delivery_id: hd(deliveries).id})

      assert {:ok, %{items: items, next_cursor: nil}} = Delivery.list_deliveries(%{})
      assert ids(items) == newest_first(deliveries)
      assert Enum.all?(items, &match?(%Ecto.Association.NotLoaded{}, &1.attempts))
    end

    test "Scenario: Pages follow the cursor" do
      expected = newest_first(for _ <- 1..5, do: delivery_fixture())

      assert {:ok, %{items: page1, next_cursor: cursor1}} = Delivery.list_deliveries(%{limit: 2})

      assert {:ok, %{items: page2, next_cursor: cursor2}} =
               Delivery.list_deliveries(%{limit: 2, cursor: cursor1})

      assert {:ok, %{items: page3, next_cursor: nil}} =
               Delivery.list_deliveries(%{limit: 2, cursor: cursor2})

      assert Enum.map([page1, page2, page3], &length/1) == [2, 2, 1]
      assert ids(page1 ++ page2 ++ page3) == expected
    end

    test "Scenario: Default limit" do
      {endpoint, _secret} = endpoint_fixture()
      for _ <- 1..21, do: delivery_fixture(%{endpoint_id: endpoint.id})

      assert {:ok, %{items: items, next_cursor: cursor}} = Delivery.list_deliveries(%{})
      assert length(items) == 20
      assert is_binary(cursor)
    end

    test "Scenario: Invalid cursor" do
      delivery_fixture()

      assert {:error, :invalid_cursor} = Delivery.list_deliveries(%{cursor: "not-a-cursor"})
    end
  end

  describe "Requirement: Endpoint health" do
    test "Scenario: Deliveries counted per status" do
      {endpoint, _secret} = endpoint_fixture()

      for status <- ~w(pending failed failed succeeded succeeded succeeded) do
        delivery_fixture(%{endpoint_id: endpoint.id, status: status})
      end

      _other = delivery_fixture(%{status: "failed"})

      assert Delivery.count_by_status(endpoint.id) ==
               %{pending: 1, succeeded: 3, failed: 2, skipped: 0}
    end

    test "Scenario: Unknown or malformed endpoint counts zero" do
      zero = %{pending: 0, succeeded: 0, failed: 0, skipped: 0}

      assert Delivery.count_by_status(Ecto.UUID.generate()) == zero
      assert Delivery.count_by_status("not-a-uuid") == zero
    end
  end
end
