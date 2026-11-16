defmodule CourierWeb.AdminDashboardTest do
  # The app env and the primary log level are global.
  use CourierWeb.ConnCase, async: false

  import CourierWeb.LogCapture, only: [capture_debug_log: 1]

  @path "/admin/dashboard"

  defp admin_token, do: Application.fetch_env!(:courier, :admin_token)

  defp with_password(conn, password, user \\ "admin") do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(user, password))
  end

  describe "Requirement: Admin-only dashboard" do
    test "Scenario: Correct token", %{conn: conn} do
      {body, log} =
        capture_debug_log(fn ->
          redirected = conn |> with_password(admin_token()) |> get(@path)
          location = redirected_to(redirected, 302)
          assert String.starts_with?(location, @path <> "/")

          # The user name is ignored.
          served = build_conn() |> with_password(admin_token(), "anyone") |> get(location)
          html_response(served, 200)
        end)

      assert body =~ "Dashboard"
      refute log =~ admin_token()
      refute log =~ Base.encode64("admin:" <> admin_token())
    end

    test "Scenario: Missing or wrong token", %{conn: conn} do
      wrong = admin_token() <> "x"

      {responses, log} =
        capture_debug_log(fn ->
          [
            get(conn, @path),
            build_conn() |> with_password(wrong) |> get(@path),
            build_conn() |> with_password("") |> get(@path),
            build_conn() |> with_password(wrong) |> get(@path <> "/home"),
            build_conn()
            |> put_req_header("authorization", "Bearer " <> admin_token())
            |> get(@path)
          ]
        end)

      for response <- responses do
        assert response.status == 401
        assert response.halted
        assert [challenge] = get_resp_header(response, "www-authenticate")
        assert challenge =~ "Basic"
        refute response.resp_body =~ admin_token()
      end

      refute log =~ admin_token()
      refute log =~ wrong
    end

    test "Scenario: Dashboard disabled", %{conn: conn} do
      token = admin_token()
      on_exit(fn -> Application.put_env(:courier, :admin_token, token) end)

      Application.delete_env(:courier, :admin_token)

      assert conn |> get(@path) |> response(404)
      assert build_conn() |> with_password(token) |> get(@path) |> response(404)

      # An empty token is not a token: an empty password must not get in.
      Application.put_env(:courier, :admin_token, "")
      assert build_conn() |> with_password("") |> get(@path) |> response(404)
    end

    test "the development route is gone", %{conn: conn} do
      assert conn |> with_password(admin_token()) |> get("/dev/dashboard") |> response(404)
    end
  end
end
