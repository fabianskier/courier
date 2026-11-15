defmodule Courier.MerchantEndpointsTest do
  use Courier.DataCase, async: true

  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Endpoints
  alias Courier.Merchants

  describe "Requirement: Update and disable merchants" do
    test "Scenario: Disable a merchant" do
      merchant = merchant_fixture()
      {enabled, _} = endpoint_fixture(%{merchant_id: merchant.id})
      {disabled, _} = endpoint_fixture(%{merchant_id: merchant.id})
      {:ok, _} = Endpoints.update_endpoint(disabled, %{enabled: false})

      assert {:ok, %{enabled: false}} = Merchants.update_merchant(merchant, %{enabled: false})
      assert {:ok, %{enabled: true}} = Endpoints.get_endpoint(enabled.id)
      assert {:ok, %{enabled: false}} = Endpoints.get_endpoint(disabled.id)
    end
  end
end
