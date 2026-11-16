defmodule CourierWeb.EndpointHealthApiTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures
  import Ecto.Query

  alias Courier.Endpoints.Endpoint
  alias Courier.Repo

  defp authed(conn) do
    %{token: token} = api_key_fixture(%{scopes: ["read"]})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  # The health columns are never cast; set them directly as delivery would.
  defp set_health(%Endpoint{id: id}, failures, degraded_at) do
    {1, _} =
      Repo.update_all(from(e in Endpoint, where: e.id == ^id),
        set: [consecutive_failures: failures, degraded_at: degraded_at]
      )

    :ok
  end

  defp list_ids(conn, query) do
    conn
    |> authed()
    |> get(~p"/api/v1/endpoints?#{query}")
    |> json_response(200)
    |> Map.fetch!("data")
    |> Enum.map(& &1["id"])
  end

  describe "Requirement: Endpoint health is visible" do
    test "Scenario: Health in the response", %{conn: conn} do
      {endpoint, _secret} = endpoint_fixture()
      :ok = set_health(endpoint, 2, nil)

      assert %{"data" => data} =
               conn |> authed() |> get(~p"/api/v1/endpoints/#{endpoint.id}") |> json_response(200)

      assert data["consecutive_failures"] == 2
      assert data["degraded"] == false
      assert Map.has_key?(data, "degraded_at")
      assert data["degraded_at"] == nil
    end

    test "Scenario: Health in the response (degraded endpoint)", %{conn: conn} do
      {endpoint, _secret} = endpoint_fixture()
      degraded_at = ~U[2026-11-15 10:00:00.123456Z]
      :ok = set_health(endpoint, 20, degraded_at)

      assert %{"data" => data} =
               conn |> authed() |> get(~p"/api/v1/endpoints/#{endpoint.id}") |> json_response(200)

      assert data["consecutive_failures"] == 20
      assert data["degraded"] == true
      assert data["degraded_at"] == DateTime.to_iso8601(degraded_at)
    end

    test "Scenario: List degraded endpoints", %{conn: conn} do
      merchant = merchant_fixture()
      {healthy, _} = endpoint_fixture(%{merchant_id: merchant.id})
      {degraded, _} = endpoint_fixture(%{merchant_id: merchant.id})
      :ok = set_health(degraded, 20, ~U[2026-11-15 10:00:00.000000Z])

      assert list_ids(conn, merchant_id: merchant.id, degraded: "true") == [degraded.id]
      assert list_ids(conn, merchant_id: merchant.id, degraded: "false") == [healthy.id]

      assert Enum.sort(list_ids(conn, merchant_id: merchant.id, degraded: "maybe")) ==
               Enum.sort([healthy.id, degraded.id])

      assert Enum.sort(list_ids(conn, merchant_id: merchant.id)) ==
               Enum.sort([healthy.id, degraded.id])
    end
  end
end
