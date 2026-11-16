defmodule Courier.PaginationDescTest do
  use Courier.DataCase, async: true

  import Courier.EventsFixtures

  alias Courier.Ingestion.Event
  alias Courier.Pagination

  defp newest_first(rows) do
    rows
    |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id}, :desc)
    |> Enum.map(& &1.id)
  end

  describe "Requirement: Read events" do
    test "newest-first pages cover every event once" do
      merchant = Courier.MerchantsFixtures.merchant_fixture()
      ids = newest_first(for _ <- 1..5, do: event_fixture(%{merchant_id: merchant.id}))

      assert {:ok, %{items: page1, next_cursor: cursor1}} =
               Pagination.paginate(Event, %{limit: 2, order: :desc})

      assert {:ok, %{items: page2, next_cursor: cursor2}} =
               Pagination.paginate(Event, %{limit: 2, cursor: cursor1, order: :desc})

      assert {:ok, %{items: page3, next_cursor: nil}} =
               Pagination.paginate(Event, %{limit: 2, cursor: cursor2, order: :desc})

      assert Enum.map([page1, page2, page3], &length/1) == [2, 2, 1]
      assert Enum.map(page1 ++ page2 ++ page3, & &1.id) == ids
    end

    test "events sharing a creation time are ordered by id descending without repeats" do
      now = DateTime.utc_now()
      merchant = Courier.MerchantsFixtures.merchant_fixture()

      for _ <- 1..3 do
        event = event_fixture(%{merchant_id: merchant.id})
        Repo.update_all(from(e in Event, where: e.id == ^event.id), set: [inserted_at: now])
      end

      {:ok, %{items: first, next_cursor: cursor}} =
        Pagination.paginate(Event, %{limit: 2, order: :desc})

      {:ok, %{items: rest, next_cursor: nil}} =
        Pagination.paginate(Event, %{limit: 2, cursor: cursor, order: :desc})

      ids = Enum.map(first ++ rest, & &1.id)
      assert length(ids) == 3
      assert ids == Enum.sort(ids, :desc)
    end

    test "the default order stays oldest first" do
      merchant = Courier.MerchantsFixtures.merchant_fixture()
      ids = newest_first(for _ <- 1..3, do: event_fixture(%{merchant_id: merchant.id}))

      assert {:ok, %{items: items, next_cursor: nil}} = Pagination.paginate(Event, %{limit: 5})
      assert Enum.map(items, & &1.id) == Enum.reverse(ids)
    end
  end
end
