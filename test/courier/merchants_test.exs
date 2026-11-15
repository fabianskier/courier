defmodule Courier.MerchantsTest do
  use Courier.DataCase, async: true

  import Courier.MerchantsFixtures

  alias Courier.Merchants
  alias Courier.Merchants.Merchant

  describe "Requirement: Create merchants" do
    test "Scenario: Merchant created" do
      assert {:ok, %Merchant{} = merchant} = Merchants.create_merchant(%{name: "  Acme Shop "})

      assert merchant.name == "Acme Shop"
      assert merchant.enabled == true
      assert {:ok, _} = Ecto.UUID.cast(merchant.id)
      assert %DateTime{} = merchant.inserted_at
    end

    test "new merchants are enabled even if asked otherwise" do
      assert {:ok, %Merchant{enabled: true}} =
               Merchants.create_merchant(%{name: "Acme", enabled: false})
    end

    test "Scenario: Invalid name" do
      for attrs <- [%{}, %{name: ""}, %{name: "   "}, %{name: String.duplicate("a", 256)}] do
        assert {:error, changeset} = Merchants.create_merchant(attrs)
        assert %{name: [_ | _]} = errors_on(changeset)
      end

      assert Repo.aggregate(Merchant, :count) == 0
    end
  end

  describe "Requirement: Show and list merchants" do
    test "Scenario: Show a merchant" do
      merchant = merchant_fixture()
      assert {:ok, %Merchant{id: id}} = Merchants.get_merchant(merchant.id)
      assert id == merchant.id
    end

    test "Scenario: Unknown merchant" do
      assert Merchants.get_merchant(Ecto.UUID.generate()) == {:error, :not_found}
      assert Merchants.get_merchant("not-a-uuid") == {:error, :not_found}
      assert Merchants.get_merchant(nil) == {:error, :not_found}
    end

    test "Scenario: List merchants" do
      ids =
        for(name <- ~w(a b c), do: merchant_fixture(%{name: name}))
        |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id})
        |> Enum.map(& &1.id)

      assert {:ok, %{items: items, next_cursor: nil}} = Merchants.list_merchants(%{limit: 50})
      assert Enum.map(items, & &1.id) == ids
    end
  end

  describe "Requirement: Update and disable merchants" do
    test "Scenario: Rename a merchant" do
      merchant = merchant_fixture(%{name: "Acme Shop"})

      assert {:ok, %Merchant{name: "Acme Store"}} =
               Merchants.update_merchant(merchant, %{name: "Acme Store"})

      assert {:ok, %Merchant{name: "Acme Store"}} = Merchants.get_merchant(merchant.id)
    end

    test "Scenario: Disable a merchant" do
      merchant = merchant_fixture()

      assert {:ok, %Merchant{enabled: false}} =
               Merchants.update_merchant(merchant, %{enabled: false})

      assert {:ok, %Merchant{enabled: false}} = Merchants.get_merchant(merchant.id)
    end

    test "invalid updates are rejected" do
      merchant = merchant_fixture(%{name: "Acme"})

      assert {:error, changeset} = Merchants.update_merchant(merchant, %{name: ""})
      assert %{name: [_ | _]} = errors_on(changeset)

      assert {:error, changeset} = Merchants.update_merchant(merchant, %{enabled: nil})
      assert %{enabled: [_ | _]} = errors_on(changeset)

      assert {:ok, %Merchant{name: "Acme", enabled: true}} = Merchants.get_merchant(merchant.id)
    end
  end
end
