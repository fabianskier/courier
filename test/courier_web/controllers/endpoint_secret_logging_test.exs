defmodule CourierWeb.EndpointSecretLoggingTest do
  # Not async: the primary log level is global and is lowered during each test.
  use CourierWeb.ConnCase, async: false

  import Courier.AccessFixtures
  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  setup do
    Logger.put_process_level(self(), :debug)
    :ok
  end

  # Ecto logs queries at :debug. The process level is only checked after the
  # primary level (:warning in test), so the primary level is lowered as well,
  # just while `fun` runs.
  defp capture_debug_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :debug)

    try do
      ExUnit.CaptureLog.with_log([level: :debug], fun)
    after
      Logger.configure(level: previous)
    end
  end

  defp authed(conn, scopes) do
    %{token: token} = api_key_fixture(%{scopes: scopes})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  # Asserts the capture worked and that no secret, nor its base64 part, was logged.
  defp refute_logged(log, secrets) do
    assert log != "", "expected captured debug logs, got none"

    for "whsec_" <> base64 = secret <- secrets do
      refute log =~ secret
      refute log =~ base64
    end
  end

  describe "Requirement: Signing secrets never appear in logs" do
    test "Scenario: Creating an endpoint logs no secret", %{conn: conn} do
      merchant = merchant_fixture()
      conn = authed(conn, ["write"])

      {conn, log} =
        capture_debug_log(fn ->
          post(conn, ~p"/api/v1/endpoints", %{
            merchant_id: merchant.id,
            url: "https://hooks.public.test/courier"
          })
        end)

      assert %{"data" => %{"secret" => "whsec_" <> _ = secret}} = json_response(conn, 201)
      refute_logged(log, [secret])
    end

    test "Scenario: Rotating a secret logs no secret", %{conn: conn} do
      {endpoint, old_secret} = endpoint_fixture()
      conn = authed(conn, ["write"])

      {conn, log} =
        capture_debug_log(fn ->
          post(conn, ~p"/api/v1/endpoints/#{endpoint.id}/rotate_secret")
        end)

      assert %{"data" => %{"secret" => "whsec_" <> _ = new_secret}} = json_response(conn, 200)
      refute_logged(log, [new_secret, old_secret])
    end
  end
end
