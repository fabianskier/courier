defmodule CourierWeb.FallbackControllerTest do
  use CourierWeb.ConnCase, async: true

  alias CourierWeb.FallbackController

  describe "Requirement: Consistent API error shape" do
    test "maps :unauthorized to 401", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unauthorized})

      assert %{"error" => %{"code" => "unauthorized", "message" => _}} = json_response(conn, 401)
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "maps :forbidden to 403", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :forbidden})

      assert %{"error" => %{"code" => "forbidden", "message" => _}} = json_response(conn, 403)
    end

    test "maps :not_found to 404", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})

      assert %{"error" => %{"code" => "not_found", "message" => _}} = json_response(conn, 404)
    end

    test "maps a changeset to 422 with field details", %{conn: conn} do
      {:error, changeset} = Courier.Access.create_key(%{name: "", scopes: ["admin"]})

      conn = FallbackController.call(conn, {:error, changeset})

      assert %{"error" => %{"code" => "invalid", "message" => _, "details" => details}} =
               json_response(conn, 422)

      assert %{"name" => [_ | _], "scopes" => [_ | _]} = details
    end
  end
end
