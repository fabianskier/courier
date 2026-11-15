defmodule CourierWeb.TokenLoggingTest do
  # Not async: capture_debug_log/1 lowers the global primary log level.
  use CourierWeb.ConnCase, async: false

  import CourierWeb.LogCapture

  describe "Requirement: Tokens never leak" do
    test "Scenario: Rejected token not echoed", %{conn: conn} do
      token = "ck_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      {conn, log} = capture_debug_log(fn -> get(conn, ~p"/api/v1/me") end)

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
      assert log != "", "expected captured debug logs, got none"
      refute log =~ token
      refute conn.resp_body =~ token
    end
  end
end
