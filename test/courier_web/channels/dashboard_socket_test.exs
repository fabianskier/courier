defmodule CourierWeb.DashboardSocketTest do
  # Not async: the key check interval is global application config.
  use CourierWeb.ChannelCase, async: false

  import Courier.AccessFixtures

  alias Courier.Access
  alias CourierWeb.DashboardChannel
  alias CourierWeb.DashboardSocket

  defp connect_with(token), do: connect(DashboardSocket, %{}, connect_info: %{auth_token: token})

  defp with_key_check_interval(ms) do
    previous = Application.fetch_env(:courier, DashboardChannel)
    Application.put_env(:courier, DashboardChannel, key_check_interval: ms)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:courier, DashboardChannel, value)
        :error -> Application.delete_env(:courier, DashboardChannel)
      end
    end)
  end

  defp join_and_monitor(token, topic) do
    {:ok, socket} = connect_with(token)
    {:ok, _reply, channel} = subscribe_and_join(socket, DashboardChannel, topic)
    {channel.channel_pid, Process.monitor(channel.channel_pid)}
  end

  describe "Requirement: Authenticated dashboard socket" do
    test "Scenario: Socket with a read key" do
      %{key: key, token: token} = api_key_fixture(%{scopes: ["read"]})

      assert {:ok, socket} = connect_with(token)
      assert socket.assigns.api_key_id == key.id
      assert DashboardSocket.id(socket) == nil
    end

    test "Scenario: Socket refused" do
      %{token: ingest_only} = api_key_fixture(%{scopes: ["ingest"]})
      %{key: revoked_key, token: revoked} = api_key_fixture(%{scopes: ["read"]})
      {:ok, _} = Access.revoke_key(revoked_key.name)
      %{token: read_token} = api_key_fixture(%{scopes: ["read"]})

      # Without a key.
      assert :error = connect(DashboardSocket, %{})
      assert :error = connect_with(nil)
      # Unknown key.
      assert :error = connect_with("ck_unknown")
      # Ingest scope only, and revoked.
      assert :error = connect_with(ingest_only)
      assert :error = connect_with(revoked)
      # A key given as a URL parameter is not accepted.
      assert :error = connect(DashboardSocket, %{"token" => read_token})
    end

    test "Scenario: Revoked key disconnected" do
      # The default check runs every 30 seconds; a short interval keeps the
      # test fast while exercising the same periodic schedule.
      with_key_check_interval(20)

      %{key: key, token: token} = api_key_fixture(%{scopes: ["read"]})
      {pid, ref} = join_and_monitor(token, "dashboard:events")

      # While the key is active, the periodic check keeps the channel open.
      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 100

      # Revocation as `mix courier.keys.revoke` does it: straight in the
      # database, without telling the channel.
      {:ok, _} = Access.revoke_key(key.name)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000

      # A key that lost the `read` scope is closed the same way.
      %{key: other_key, token: other_token} = api_key_fixture(%{scopes: ["read"]})
      {other_pid, other_ref} = join_and_monitor(other_token, "dashboard:merchants")

      other_key
      |> Ecto.Changeset.change(scopes: ["ingest"])
      |> Courier.Repo.update!()

      assert_receive {:DOWN, ^other_ref, :process, ^other_pid, :normal}, 1_000
    end
  end
end
