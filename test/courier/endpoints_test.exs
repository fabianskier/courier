defmodule Courier.EndpointsTest do
  use Courier.DataCase, async: true

  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Endpoints
  alias Courier.Endpoints.Endpoint

  @url "https://hooks.public.test/courier"

  describe "Requirement: Create endpoints" do
    test "Scenario: Endpoint for unknown merchant" do
      for merchant_id <- [Ecto.UUID.generate(), "not-a-uuid", nil] do
        assert {:error, changeset} =
                 Endpoints.create_endpoint(%{merchant_id: merchant_id, url: @url})

        assert %{merchant_id: [_ | _]} = errors_on(changeset)
      end

      assert Repo.aggregate(Endpoint, :count) == 0
    end
  end

  describe "Requirement: Delivery settings" do
    test "Scenario: Defaults applied" do
      {endpoint, _secret} = endpoint_fixture()

      assert {:ok, %Endpoint{retry_window_seconds: 86_400, retry_on_4xx: false} = loaded} =
               Endpoints.get_endpoint(endpoint.id)

      assert loaded.max_concurrency == 10
      assert loaded.enabled == true
    end

    test "Scenario: Setting out of range" do
      {endpoint, _secret} = endpoint_fixture()
      invalid = [retry_window_seconds: 90_000, retry_window_seconds: 59, max_concurrency: 0]

      for {field, value} <- invalid ++ [max_concurrency: 51] do
        attrs = %{merchant_id: endpoint.merchant_id, url: @url}
        assert {:error, changeset} = Endpoints.create_endpoint(Map.put(attrs, field, value))
        assert Map.has_key?(errors_on(changeset), field)

        assert {:error, changeset} = Endpoints.update_endpoint(endpoint, %{field => value})
        assert Map.has_key?(errors_on(changeset), field)
      end
    end
  end

  describe "Requirement: Show, list, update and disable endpoints" do
    test "Scenario: Unsafe URL on update" do
      {endpoint, _secret} = endpoint_fixture()

      for url <- ["https://10.0.0.5/", "https://hooks.private.test/", "http://hooks.public.test/"] do
        assert {:error, changeset} = Endpoints.update_endpoint(endpoint, %{url: url})
        assert %{url: ["must be a public https URL"]} = errors_on(changeset)
      end

      assert {:ok, %Endpoint{url: @url}} = Endpoints.get_endpoint(endpoint.id)
    end

    test "lists endpoints for one merchant" do
      merchant = merchant_fixture()
      {mine, _} = endpoint_fixture(%{merchant_id: merchant.id})
      {_other, _} = endpoint_fixture()

      assert {:ok, %{items: [%Endpoint{id: id}], next_cursor: nil}} =
               Endpoints.list_endpoints(%{limit: 10, merchant_id: merchant.id})

      assert id == mine.id
    end
  end

  describe "Requirement: Signing secrets" do
    test "Scenario: Secret format" do
      {_endpoint, "whsec_" <> encoded} = endpoint_fixture()
      assert {:ok, raw} = Base.decode64(encoded)
      assert byte_size(raw) == 32
    end

    test "Scenario: Secret encrypted at rest" do
      {endpoint, "whsec_" <> encoded = secret} = endpoint_fixture()
      raw = Base.decode64!(encoded)

      %{rows: [[stored, row_text]]} =
        Repo.query!("SELECT e.secret, e::text FROM endpoints e WHERE e.id = $1", [
          Ecto.UUID.dump!(endpoint.id)
        ])

      for needle <- [secret, encoded, raw, Base.encode16(raw, case: :lower)] do
        assert :binary.match(stored, needle) == :nomatch
        assert :binary.match(row_text, needle) == :nomatch
      end

      assert {:ok, %Endpoint{secret: ^secret}} = Endpoints.get_endpoint(endpoint.id)
    end

    test "inspect/1 shows no secret" do
      {endpoint, "whsec_" <> encoded} = endpoint_fixture()
      {:ok, loaded} = Endpoints.get_endpoint(endpoint.id)

      for struct <- [endpoint, loaded] do
        refute inspect(struct) =~ encoded
        refute inspect(struct) =~ "secret:"
      end
    end
  end
end
