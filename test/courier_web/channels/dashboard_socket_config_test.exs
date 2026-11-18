defmodule CourierWeb.DashboardSocketConfigTest do
  # Channel tests call `connect/3` directly, so they cannot see whether the
  # endpoint really hands the auth token to the socket. Phoenix copies the
  # top-level `auth_token` option into each transport and overwrites one set
  # inside `websocket:`, which once left every dashboard socket refused.
  use ExUnit.Case, async: true

  test "the dashboard socket enables the auth token at the top level" do
    assert {"/socket", CourierWeb.DashboardSocket, opts} =
             Enum.find(CourierWeb.Endpoint.__sockets__(), &(elem(&1, 0) == "/socket"))

    assert opts[:auth_token] == true
    assert opts[:longpoll] == false
  end
end
