defmodule Courier.EndpointsFixtures do
  @moduledoc """
  Test helpers for creating endpoints through `Courier.Endpoints`.

  URLs use `*.public.test` hosts, which `Courier.Endpoints.TestResolver`
  resolves to a public address without touching the network.
  """

  import Courier.MerchantsFixtures

  @doc """
  Creates an endpoint and returns it. Creates a merchant unless `merchant_id`
  is given.
  """
  def endpoint_fixture(attrs \\ %{}) do
    {endpoint, _secret} = endpoint_with_secret_fixture(attrs)
    endpoint
  end

  @doc "Creates an endpoint and returns `{endpoint, secret}`."
  def endpoint_with_secret_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new_lazy(:merchant_id, fn -> merchant_fixture().id end)
      |> Map.put_new(:url, "https://hooks.public.test/courier")

    {:ok, endpoint, secret} = Courier.Endpoints.create_endpoint(attrs)
    {endpoint, secret}
  end
end
