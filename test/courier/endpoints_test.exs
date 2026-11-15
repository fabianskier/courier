defmodule Courier.EndpointsTest do
  use Courier.DataCase, async: true

  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Endpoints
  alias Courier.Endpoints.Endpoint

  describe "Requirement: Create endpoints" do
    test "creates an enabled endpoint with its patterns" do
      merchant = merchant_fixture()

      assert {:ok, %Endpoint{} = endpoint, "whsec_" <> _} =
               Endpoints.create_endpoint(%{
                 merchant_id: merchant.id,
                 url: "https://hooks.public.test/courier",
                 description: "Main",
                 event_types: ["payment.*", "payment.*", "refund.failed"],
                 enabled: false
               })

      assert endpoint.merchant_id == merchant.id
      assert endpoint.enabled == true
      assert endpoint.event_types == ["payment.*", "refund.failed"]

      assert {:ok, %Endpoint{url: "https://hooks.public.test/courier"}} =
               Endpoints.get_endpoint(endpoint.id)
    end

    test "Scenario: Endpoint for unknown merchant" do
      for merchant_id <- [Ecto.UUID.generate(), "not-a-uuid", nil] do
        assert {:error, changeset} =
                 Endpoints.create_endpoint(%{
                   merchant_id: merchant_id,
                   url: "https://hooks.public.test/courier"
                 })

        assert %{merchant_id: [_ | _]} = errors_on(changeset)
      end

      assert Repo.aggregate(Endpoint, :count) == 0
    end

    test "rejects unsafe URLs and invalid patterns" do
      merchant = merchant_fixture()

      assert {:error, changeset} =
               Endpoints.create_endpoint(%{
                 merchant_id: merchant.id,
                 url: "http://hooks.public.test/"
               })

      assert %{url: ["must be a public https URL"]} = errors_on(changeset)

      assert {:error, changeset} =
               Endpoints.create_endpoint(%{
                 merchant_id: merchant.id,
                 url: "https://hooks.public.test/",
                 event_types: ["payment.*", "*"]
               })

      assert %{event_types: [_ | _]} = errors_on(changeset)

      too_many = for i <- 1..51, do: "type#{i}"

      assert {:error, changeset} =
               Endpoints.create_endpoint(%{
                 merchant_id: merchant.id,
                 url: "https://hooks.public.test/",
                 event_types: too_many
               })

      assert %{event_types: [_ | _]} = errors_on(changeset)
    end
  end

  describe "Requirement: Delivery settings" do
    test "Scenario: Defaults applied" do
      endpoint = endpoint_fixture()

      assert endpoint.retry_window_seconds == 86_400
      assert endpoint.retry_on_4xx == false
      assert endpoint.max_concurrency == 10

      assert {:ok,
              %Endpoint{retry_window_seconds: 86_400, retry_on_4xx: false, max_concurrency: 10}} =
               Endpoints.get_endpoint(endpoint.id)
    end

    test "Scenario: Setting out of range" do
      merchant = merchant_fixture()
      base = %{merchant_id: merchant.id, url: "https://hooks.public.test/"}

      for {field, value} <- [
            retry_window_seconds: 90_000,
            retry_window_seconds: 59,
            max_concurrency: 0,
            max_concurrency: 51
          ] do
        assert {:error, changeset} = Endpoints.create_endpoint(Map.put(base, field, value))
        assert Map.has_key?(errors_on(changeset), field)
      end

      endpoint = endpoint_fixture()

      for {field, value} <- [retry_window_seconds: 90_000, max_concurrency: 0] do
        assert {:error, changeset} = Endpoints.update_endpoint(endpoint, %{field => value})
        assert Map.has_key?(errors_on(changeset), field)
      end

      assert {:ok, %Endpoint{retry_window_seconds: 60, max_concurrency: 50, retry_on_4xx: true}} =
               Endpoints.update_endpoint(endpoint, %{
                 retry_window_seconds: 60,
                 max_concurrency: 50,
                 retry_on_4xx: true
               })
    end
  end

  describe "Requirement: Show, list, update and disable endpoints" do
    test "Scenario: Unsafe URL on update" do
      endpoint = endpoint_fixture(%{url: "https://hooks.public.test/old"})

      for url <- ["https://10.0.0.5/", "https://hooks.private.test/", "https://nowhere.test/"] do
        assert {:error, changeset} = Endpoints.update_endpoint(endpoint, %{url: url})
        assert %{url: ["must be a public https URL"]} = errors_on(changeset)
      end

      assert {:ok, %Endpoint{url: "https://hooks.public.test/old"}} =
               Endpoints.get_endpoint(endpoint.id)
    end

    test "unknown or malformed ids are not found" do
      assert Endpoints.get_endpoint(Ecto.UUID.generate()) == {:error, :not_found}
      assert Endpoints.get_endpoint("not-a-uuid") == {:error, :not_found}
      assert Endpoints.get_endpoint(nil) == {:error, :not_found}
    end

    test "lists endpoints oldest first, optionally for one merchant" do
      merchant = merchant_fixture()
      mine = for _ <- 1..3, do: endpoint_fixture(%{merchant_id: merchant.id})
      other = endpoint_fixture()

      assert {:ok, %{items: page1, next_cursor: cursor}} =
               Endpoints.list_endpoints(%{limit: 2, merchant_id: merchant.id})

      assert {:ok, %{items: page2, next_cursor: nil}} =
               Endpoints.list_endpoints(%{limit: 2, cursor: cursor, merchant_id: merchant.id})

      assert Enum.sort(Enum.map(page1 ++ page2, & &1.id)) == Enum.sort(Enum.map(mine, & &1.id))

      assert {:ok, %{items: all}} = Endpoints.list_endpoints(%{limit: 50})
      assert other.id in Enum.map(all, & &1.id)
      assert length(all) == 4

      assert {:ok, %{items: []}} = Endpoints.list_endpoints(%{limit: 50, merchant_id: "bad"})
    end

    test "updates and disables an endpoint" do
      endpoint = endpoint_fixture()

      assert {:ok, %Endpoint{enabled: false, description: "Backup", event_types: ["order.*"]}} =
               Endpoints.update_endpoint(endpoint, %{
                 enabled: false,
                 description: "Backup",
                 event_types: ["order.*"]
               })

      assert {:ok, %{items: [%Endpoint{enabled: false}]}} =
               Endpoints.list_endpoints(%{limit: 50, merchant_id: endpoint.merchant_id})
    end
  end

  describe "Requirement: Signing secrets" do
    test "Scenario: Secret format" do
      {endpoint, secret} = endpoint_with_secret_fixture()

      assert "whsec_" <> encoded = secret
      assert {:ok, raw} = Base.decode64(encoded)
      assert byte_size(raw) == 32

      assert {:ok, %Endpoint{secret: ^secret}} = Endpoints.get_endpoint(endpoint.id)
    end

    test "Scenario: Secret encrypted at rest" do
      {endpoint, "whsec_" <> encoded = secret} = endpoint_with_secret_fixture()
      raw = Base.decode64!(encoded)

      %{rows: [[stored, row_text]]} =
        Repo.query!("SELECT e.secret, e::text FROM endpoints e WHERE e.id = $1", [
          Ecto.UUID.dump!(endpoint.id)
        ])

      for needle <- [secret, encoded, raw] do
        assert :binary.match(stored, needle) == :nomatch
        assert :binary.match(row_text, needle) == :nomatch
      end

      assert :binary.match(row_text, Base.encode16(raw, case: :lower)) == :nomatch
    end

    test "inspect/1 shows no secret" do
      {endpoint, "whsec_" <> encoded = secret} = endpoint_with_secret_fixture()
      {:ok, loaded} = Endpoints.get_endpoint(endpoint.id)

      for struct <- [endpoint, loaded] do
        inspected = inspect(struct)
        refute inspected =~ secret
        refute inspected =~ encoded
        refute inspected =~ "secret:"
      end
    end
  end
end
