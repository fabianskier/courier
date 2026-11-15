defmodule CourierWeb.MerchantControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.AccessFixtures
  import Courier.MerchantsFixtures

  alias Courier.Merchants
  alias Courier.Merchants.Merchant
  alias Courier.Repo

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp assert_error(conn, status, code) do
    assert %{"error" => %{"code" => ^code}} = body = json_response(conn, status)
    body
  end

  describe "Requirement: Create merchants" do
    test "Scenario: Merchant created", %{conn: conn} do
      conn = post(authed(conn, ["write"]), ~p"/api/v1/merchants", %{name: "Acme Shop"})

      assert %{"data" => data} = json_response(conn, 201)
      assert %{"id" => id, "name" => "Acme Shop", "enabled" => true} = data
      assert {:ok, _inserted_at, 0} = DateTime.from_iso8601(data["inserted_at"])
      assert {:ok, %Merchant{name: "Acme Shop"}} = Merchants.get_merchant(id)
    end

    test "Scenario: Invalid name", %{conn: conn} do
      conn = authed(conn, ["write"])

      for params <- [%{name: ""}, %{name: "   "}, %{}] do
        body = conn |> post(~p"/api/v1/merchants", params) |> assert_error(422, "invalid")
        assert %{"error" => %{"details" => %{"name" => [_ | _]}}} = body
      end

      assert Repo.aggregate(Merchant, :count) == 0
    end
  end

  describe "Requirement: Show and list merchants" do
    test "Scenario: Show a merchant", %{conn: conn} do
      merchant = merchant_fixture(%{name: "Acme Shop"})

      conn = get(authed(conn, ["read"]), ~p"/api/v1/merchants/#{merchant.id}")

      assert %{"data" => %{"id" => id, "name" => "Acme Shop", "enabled" => true}} =
               json_response(conn, 200)

      assert id == merchant.id
    end

    test "Scenario: Unknown merchant", %{conn: conn} do
      conn = authed(conn, ["read"])

      for id <- [Ecto.UUID.generate(), "not-a-uuid", "123"] do
        conn |> get(~p"/api/v1/merchants/#{id}") |> assert_error(404, "not_found")
      end
    end

    test "Scenario: List merchants", %{conn: conn} do
      ids = for name <- ["one", "two", "three"], do: merchant_fixture(%{name: name}).id

      conn = get(authed(conn, ["read"]), ~p"/api/v1/merchants")

      assert %{"data" => data, "next_cursor" => nil} = json_response(conn, 200)
      assert Enum.map(data, & &1["id"]) == ids
      assert Enum.map(data, & &1["name"]) == ["one", "two", "three"]
    end
  end

  describe "Requirement: Update and disable merchants" do
    test "Scenario: Rename a merchant", %{conn: conn} do
      merchant = merchant_fixture(%{name: "Acme Shop"})

      conn =
        patch(authed(conn, ["write"]), ~p"/api/v1/merchants/#{merchant.id}", %{
          name: "Acme Store"
        })

      assert %{"data" => %{"name" => "Acme Store", "enabled" => true}} =
               json_response(conn, 200)

      assert {:ok, %Merchant{name: "Acme Store"}} = Merchants.get_merchant(merchant.id)
    end

    test "Scenario: Disable a merchant", %{conn: conn} do
      merchant = merchant_fixture(%{name: "Acme Shop"})

      conn =
        patch(authed(conn, ["write"]), ~p"/api/v1/merchants/#{merchant.id}", %{enabled: false})

      assert %{"data" => %{"name" => "Acme Shop", "enabled" => false}} =
               json_response(conn, 200)

      assert {:ok, %Merchant{enabled: false}} = Merchants.get_merchant(merchant.id)
    end
  end

  describe "Requirement: Merchant API scopes" do
    test "Scenario: Read-only key cannot create", %{conn: conn} do
      conn
      |> authed(["read"])
      |> post(~p"/api/v1/merchants", %{name: "Acme Shop"})
      |> assert_error(403, "forbidden")

      assert Repo.aggregate(Merchant, :count) == 0
    end

    test "Scenario: Write-only key cannot list", %{conn: conn} do
      conn
      |> authed(["write"])
      |> get(~p"/api/v1/merchants")
      |> assert_error(403, "forbidden")
    end
  end

  describe "Requirement: Paginated lists" do
    test "Scenario: Two pages", %{conn: conn} do
      ids = for n <- 1..5, do: merchant_fixture(%{name: "m#{n}"}).id
      conn = authed(conn, ["read"])

      pages =
        Stream.unfold(:start, fn
          :done ->
            nil

          cursor ->
            params = if cursor == :start, do: %{limit: 2}, else: %{limit: 2, cursor: cursor}
            body = conn |> get(~p"/api/v1/merchants", params) |> json_response(200)
            page_ids = Enum.map(body["data"], & &1["id"])
            {page_ids, body["next_cursor"] || :done}
        end)
        |> Enum.to_list()

      assert Enum.map(pages, &length/1) == [2, 2, 1]
      assert List.flatten(pages) == ids
    end

    test "Scenario: Invalid pagination", %{conn: conn} do
      merchant_fixture()
      conn = authed(conn, ["read"])

      for params <- [
            %{limit: 0},
            %{limit: 101},
            %{limit: "abc"},
            %{cursor: "not-a-cursor"},
            %{cursor: Base.url_encode64("2026-01-01T00:00:00Z|nope")}
          ] do
        conn |> get(~p"/api/v1/merchants", params) |> assert_error(422, "invalid")
      end
    end
  end
end
