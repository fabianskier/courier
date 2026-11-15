defmodule Courier.MerchantEndpointsTest do
  use Courier.DataCase, async: true

  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Endpoints
  alias Courier.Endpoints.Endpoint
  alias Courier.Merchants
  alias Courier.Merchants.Merchant

  describe "Requirement: Update and disable merchants" do
    test "Scenario: Disable a merchant" do
      merchant = merchant_fixture()
      enabled = endpoint_fixture(%{merchant_id: merchant.id})

      {:ok, disabled} =
        %{merchant_id: merchant.id}
        |> endpoint_fixture()
        |> Endpoints.update_endpoint(%{enabled: false})

      assert {:ok, %Merchant{enabled: false}} =
               Merchants.update_merchant(merchant, %{enabled: false})

      assert {:ok, %Endpoint{enabled: true}} = Endpoints.get_endpoint(enabled.id)
      assert {:ok, %Endpoint{enabled: false}} = Endpoints.get_endpoint(disabled.id)
    end
  end
end
