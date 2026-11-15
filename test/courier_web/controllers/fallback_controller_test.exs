defmodule CourierWeb.FallbackControllerTest do
  use CourierWeb.ConnCase, async: true

  alias CourierWeb.FallbackController

  describe "Requirement: Consistent API error shape" do
    test "maps {:error, :unauthorized} to 401 with a Bearer challenge", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unauthorized})

      assert %{"error" => %{"code" => "unauthorized", "message" => message}} =
               json_response(conn, 401)

      assert is_binary(message) and message != ""
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "maps {:error, :forbidden} to 403", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :forbidden})

      assert %{"error" => %{"code" => "forbidden", "message" => message}} =
               json_response(conn, 403)

      assert is_binary(message) and message != ""
    end

    test "maps {:error, :not_found} to 404", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})

      assert %{"error" => %{"code" => "not_found", "message" => message}} =
               json_response(conn, 404)

      assert is_binary(message) and message != ""
    end

    test "maps a changeset to 422 with interpolated field errors in details", %{conn: conn} do
      long_name = String.duplicate("a", 256)
      {:error, changeset} = Courier.Access.create_key(%{name: long_name, scopes: ["admin"]})

      conn = FallbackController.call(conn, {:error, changeset})

      assert %{"error" => %{"code" => "invalid", "message" => message, "details" => details}} =
               json_response(conn, 422)

      assert is_binary(message) and message != ""
      assert details["name"] == ["should be at most 255 character(s)"]
      assert [_ | _] = details["scopes"]
      refute Enum.any?(details["scopes"], &String.contains?(&1, "%{"))
    end
  end
end
