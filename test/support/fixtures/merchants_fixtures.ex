defmodule Courier.MerchantsFixtures do
  @moduledoc """
  Test helpers for creating merchants through `Courier.Merchants`.
  """

  @doc "Creates a merchant. Defaults to a unique name."
  def merchant_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "merchant-#{System.unique_integer([:positive])}"})

    {:ok, merchant} = Courier.Merchants.create_merchant(attrs)
    merchant
  end
end
