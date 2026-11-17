defmodule CourierWeb.SpaControllerTest do
  # Not async: points the controller at a fixture through the app env.
  use CourierWeb.ConnCase, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    index_path = Path.join(tmp_dir, "index.html")
    previous = Application.get_env(:courier, CourierWeb.SpaController)
    Application.put_env(:courier, CourierWeb.SpaController, index_path: index_path)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:courier, CourierWeb.SpaController, previous),
        else: Application.delete_env(:courier, CourierWeb.SpaController)
    end)

    %{index_path: index_path}
  end

  describe "built dashboard" do
    setup %{index_path: index_path} do
      File.write!(index_path, ~s(<!doctype html><div id="root"></div>))
      :ok
    end

    test "serves index.html at the root", %{conn: conn} do
      conn = get(conn, "/")

      assert html_response(conn, 200) =~ ~s(<div id="root">)
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
    end

    test "serves index.html for client routes", %{conn: conn} do
      conn = get(conn, "/deliveries/0b5a6c1e-1111-4222-8333-944445555666")

      assert html_response(conn, 200) =~ ~s(<div id="root">)
    end

    test "keeps the 404 for unknown paths under server prefixes", %{conn: conn} do
      for path <- ["/api/v1/no-such-thing", "/api", "/admin/x", "/dev/dashboard", "/socket/x"] do
        assert %{"errors" => %{"detail" => "Not Found"}} = json_response(get(conn, path), 404)
      end
    end
  end

  describe "dashboard not built" do
    test "answers 404 with a hint", %{conn: conn} do
      conn = get(conn, "/")

      assert text_response(conn, 404) =~ "npm run build"
    end
  end
end
