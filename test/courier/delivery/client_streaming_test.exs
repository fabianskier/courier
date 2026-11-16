defmodule Courier.Delivery.ClientStreamingTest do
  use ExUnit.Case, async: false

  alias Courier.Delivery.Client

  @moduletag :capture_log

  @chunk_count 2560
  @chunk String.duplicate("a", 4096)

  defp start_server(plug) do
    pid = start_supervised!({Bandit, plug: plug, port: 0, ip: :loopback, startup_log: false})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/webhooks"
  end

  describe "Requirement: Bounded response reading" do
    test "Scenario: Large response body" do
      test_pid = self()

      url =
        start_server(fn conn, _opts ->
          conn = Plug.Conn.send_chunked(conn, 200)

          sent =
            Enum.reduce_while(1..@chunk_count, 0, fn _, sent ->
              case Plug.Conn.chunk(conn, @chunk) do
                {:ok, _conn} -> {:cont, sent + 1}
                {:error, _reason} -> {:halt, sent}
              end
            end)

          send(test_pid, {:chunks_sent, sent})
          conn
        end)

      assert {:ok, %{status: 200, body: body}} = Client.post(url, "{}", [], plug: nil)
      assert body == binary_part(@chunk, 0, 4096)

      assert_receive {:chunks_sent, sent}, 10_000
      assert sent < @chunk_count
    end

    test "Scenario: Body that trickles in" do
      url =
        start_server(fn conn, _opts ->
          conn = Plug.Conn.send_chunked(conn, 200)
          {:ok, conn} = Plug.Conn.chunk(conn, "a")
          Process.sleep(2_000)
          conn
        end)

      started = System.monotonic_time(:millisecond)
      assert Client.post(url, "{}", [], plug: nil, deadline: 300) == {:error, "timeout"}
      assert System.monotonic_time(:millisecond) - started < 1_500
    end
  end
end
