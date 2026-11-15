defmodule Courier.PaginationTest do
  use Courier.DataCase, async: true

  import Courier.MerchantsFixtures

  alias Courier.Merchants.Merchant
  alias Courier.Pagination

  describe "Requirement: Paginated lists" do
    test "Scenario: Two pages" do
      ids =
        for(_ <- 1..5, do: merchant_fixture())
        |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id})
        |> Enum.map(& &1.id)

      assert {:ok, %{items: page1, next_cursor: cursor1}} =
               Pagination.paginate(Merchant, %{limit: 2, cursor: nil})

      assert is_binary(cursor1)

      assert {:ok, %{items: page2, next_cursor: cursor2}} =
               Pagination.paginate(Merchant, %{limit: 2, cursor: cursor1})

      assert is_binary(cursor2)

      assert {:ok, %{items: page3, next_cursor: nil}} =
               Pagination.paginate(Merchant, %{limit: 2, cursor: cursor2})

      assert Enum.map([page1, page2, page3], &length/1) == [2, 2, 1]
      assert Enum.map(page1 ++ page2 ++ page3, & &1.id) == ids
    end

    test "rows sharing a creation time are ordered by id without repeats" do
      now = DateTime.utc_now()

      for _ <- 1..3 do
        Repo.insert!(%Merchant{name: "same", inserted_at: now, updated_at: now})
      end

      {:ok, %{items: first, next_cursor: cursor}} = Pagination.paginate(Merchant, %{limit: 2})

      {:ok, %{items: rest, next_cursor: nil}} =
        Pagination.paginate(Merchant, %{limit: 2, cursor: cursor})

      ids = Enum.map(first ++ rest, & &1.id)
      assert length(ids) == 3
      assert ids == Enum.sort(ids)
    end

    test "Scenario: Invalid pagination" do
      merchant_fixture()

      bad_cursors = [
        "not base64!",
        Base.url_encode64("garbage"),
        Base.url_encode64("2026-01-01T00:00:00.000000Z|not-a-uuid"),
        Base.url_encode64("yesterday|" <> Ecto.UUID.generate()),
        123
      ]

      for cursor <- bad_cursors do
        assert Pagination.paginate(Merchant, %{limit: 2, cursor: cursor}) ==
                 {:error, :invalid_cursor}
      end
    end
  end
end
