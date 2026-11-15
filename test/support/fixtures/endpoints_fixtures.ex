defmodule Courier.EndpointsFixtures do
  @moduledoc "Test helpers for creating endpoints through `Courier.Endpoints`."

  @doc """
  Creates an endpoint and returns `{endpoint, secret}`. Creates a merchant
  unless `merchant_id` is given; the URL host resolves through the test resolver.
  """
  def endpoint_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new_lazy(:merchant_id, fn -> Courier.MerchantsFixtures.merchant_fixture().id end)
      |> Map.put_new(:url, "https://hooks.public.test/courier")

    {:ok, endpoint, secret} = Courier.Endpoints.create_endpoint(attrs)
    {endpoint, secret}
  end
end
