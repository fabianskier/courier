defmodule CourierWeb.EndpointControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Endpoints
  alias Courier.Endpoints.Endpoint
  alias Courier.Repo

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp assert_error(conn, status, code) do
    assert %{"error" => %{"code" => ^code}} = body = json_response(conn, status)
    body
  end

  # No `secret` key anywhere and none of the given secret values in the raw body.
  defp refute_secret(conn, secrets) do
    refute conn.resp_body =~ "secret\""
    for secret <- secrets, do: refute(conn.resp_body =~ secret)
    conn
  end

  describe "Requirement: Create endpoints" do
    test "Scenario: Endpoint created", %{conn: conn} do
      merchant = merchant_fixture()

      conn =
        post(authed(conn, ["write"]), ~p"/api/v1/endpoints", %{
          merchant_id: merchant.id,
          url: "https://hooks.public.test/courier",
          event_types: ["payment.*"]
        })

      assert %{"data" => data} = json_response(conn, 201)

      assert %{
               "id" => id,
               "merchant_id" => merchant_id,
               "url" => "https://hooks.public.test/courier",
               "event_types" => ["payment.*"],
               "enabled" => true,
               "retry_window_seconds" => 86_400,
               "retry_on_4xx" => false,
               "max_concurrency" => 10,
               "secret" => "whsec_" <> _ = secret
             } = data

      assert merchant_id == merchant.id
      refute Map.has_key?(data, "previous_secret")
      assert {:ok, %Endpoint{} = endpoint} = Endpoints.get_endpoint(id)
      assert Endpoints.signing_secrets(endpoint) == [secret]
    end

    test "Scenario: Endpoint for unknown merchant", %{conn: conn} do
      body =
        conn
        |> authed(["write"])
        |> post(~p"/api/v1/endpoints", %{
          merchant_id: Ecto.UUID.generate(),
          url: "https://hooks.public.test/courier"
        })
        |> refute_secret([])
        |> assert_error(422, "invalid")

      assert %{"error" => %{"details" => %{"merchant_id" => [_ | _]}}} = body
      assert Repo.aggregate(Endpoint, :count) == 0
    end
  end

  describe "Requirement: Show, list, update and disable endpoints" do
    test "Scenario: List a merchant's endpoints", %{conn: conn} do
      merchant = merchant_fixture()
      {first, s1} = endpoint_fixture(%{merchant_id: merchant.id})
      {second, s2} = endpoint_fixture(%{merchant_id: merchant.id})
      {_other, s3} = endpoint_fixture()

      conn =
        conn
        |> authed(["read"])
        |> get(~p"/api/v1/endpoints", %{merchant_id: merchant.id})
        |> refute_secret([s1, s2, s3])

      assert %{"data" => data, "next_cursor" => nil} = json_response(conn, 200)
      assert Enum.map(data, & &1["id"]) == [first.id, second.id]
      assert Enum.all?(data, &(&1["merchant_id"] == merchant.id))
    end

    test "Scenario: Show without secret", %{conn: conn} do
      {endpoint, secret} = endpoint_fixture()

      conn =
        conn
        |> authed(["read"])
        |> get(~p"/api/v1/endpoints/#{endpoint.id}")
        |> refute_secret([secret])

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == endpoint.id
      refute Map.has_key?(data, "secret")

      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        conn
        |> recycle()
        |> authed(["read"])
        |> get(~p"/api/v1/endpoints/#{id}")
        |> assert_error(404, "not_found")
      end
    end

    test "Scenario: Disable an endpoint", %{conn: conn} do
      {endpoint, secret} = endpoint_fixture()
      write = authed(conn, ["write"])

      conn =
        write
        |> patch(~p"/api/v1/endpoints/#{endpoint.id}", %{enabled: false})
        |> refute_secret([secret])

      assert %{"data" => %{"id" => id, "enabled" => false}} = json_response(conn, 200)
      assert id == endpoint.id
      assert {:ok, %Endpoint{enabled: false}} = Endpoints.get_endpoint(endpoint.id)

      list =
        build_conn()
        |> authed(["read"])
        |> get(~p"/api/v1/endpoints", %{merchant_id: endpoint.merchant_id})
        |> refute_secret([secret])

      assert %{"data" => [%{"id" => ^id, "enabled" => false}]} = json_response(list, 200)
    end

    test "Scenario: Unsafe URL on update", %{conn: conn} do
      {endpoint, secret} = endpoint_fixture()

      body =
        conn
        |> authed(["write"])
        |> patch(~p"/api/v1/endpoints/#{endpoint.id}", %{url: "https://10.0.0.5/"})
        |> refute_secret([secret])
        |> assert_error(422, "invalid")

      assert %{"error" => %{"details" => %{"url" => [_ | _]}}} = body
      assert {:ok, %Endpoint{url: url}} = Endpoints.get_endpoint(endpoint.id)
      assert url == endpoint.url
    end
  end

  describe "Requirement: Rotate signing secrets" do
    test "Scenario: Rotation with overlap", %{conn: conn} do
      {endpoint, old_secret} = endpoint_fixture()

      conn =
        conn
        |> authed(["write"])
        |> post(~p"/api/v1/endpoints/#{endpoint.id}/rotate_secret")

      assert %{"data" => %{"id" => id, "secret" => "whsec_" <> _ = new_secret} = data} =
               json_response(conn, 200)

      assert id == endpoint.id
      assert new_secret != old_secret
      refute conn.resp_body =~ old_secret
      refute Map.has_key?(data, "previous_secret")
      assert {:ok, _expires_at, 0} = DateTime.from_iso8601(data["previous_secret_expires_at"])

      assert {:ok, rotated} = Endpoints.get_endpoint(endpoint.id)
      assert Endpoints.signing_secrets(rotated) == [new_secret, old_secret]
    end
  end

  describe "Requirement: Endpoint API scopes" do
    test "Scenario: Read-only key cannot rotate", %{conn: conn} do
      {endpoint, secret} = endpoint_fixture()

      conn
      |> authed(["read"])
      |> post(~p"/api/v1/endpoints/#{endpoint.id}/rotate_secret")
      |> refute_secret([secret])
      |> assert_error(403, "forbidden")

      assert {:ok, unchanged} = Endpoints.get_endpoint(endpoint.id)
      assert Endpoints.signing_secrets(unchanged) == [secret]
    end
  end
end
