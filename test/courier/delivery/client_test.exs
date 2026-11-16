defmodule Courier.Delivery.ClientTest do
  use ExUnit.Case, async: true

  alias Courier.Delivery.Client

  @url "https://hooks.example.com/webhooks"
  @headers [{"content-type", "application/json"}, {"webhook-id", "evt_1"}]

  defp stub(fun), do: Req.Test.stub(Client, fun)

  describe "Requirement: Successful delivery" do
    test "a 200 returns the status and body" do
      test_pid = self()

      stub(fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:request, conn.method, conn.request_path, body, conn.req_headers})
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      assert {:ok, %{status: 200, body: "ok", retry_after: nil}} =
               Client.post(@url, ~s({"id":"evt_1"}), @headers)

      assert_received {:request, "POST", "/webhooks", ~s({"id":"evt_1"}), req_headers}
      assert {"webhook-id", "evt_1"} in req_headers
    end
  end

  describe "Requirement: Non-retryable failures end the delivery" do
    test "Scenario: Redirect not followed" do
      test_pid = self()

      stub(fn
        %{request_path: "/moved"} = conn ->
          send(test_pid, :location_called)
          Plug.Conn.send_resp(conn, 200, "moved")

        conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://hooks.example.com/moved")
          |> Plug.Conn.send_resp(302, "")
      end)

      assert {:ok, %{status: 302}} = Client.post(@url, "{}", @headers)
      refute_received :location_called
    end
  end

  describe "Requirement: Retryable failures are retried" do
    test "a transport timeout is returned as {:error, \"timeout\"}" do
      stub(&Req.Test.transport_error(&1, :timeout))

      assert Client.post(@url, "{}", @headers) == {:error, "timeout"}
    end

    test "Retry-After is returned" do
      stub(fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "120")
        |> Plug.Conn.send_resp(429, "slow down")
      end)

      assert {:ok, %{status: 429, retry_after: "120"}} = Client.post(@url, "{}", @headers)
    end
  end

  describe "Requirement: Attempts are append-only" do
    test "a 10 KB body is truncated to 4096 bytes" do
      body = String.duplicate("a", 10 * 1024)
      stub(&Plug.Conn.send_resp(&1, 500, body))

      assert {:ok, %{status: 500, body: stored}} = Client.post(@url, "{}", @headers)
      assert byte_size(stored) == 4096
      assert stored == binary_part(body, 0, 4096)
    end

    test "invalid UTF-8 and NUL bytes are sanitized" do
      stub(&Plug.Conn.send_resp(&1, 400, <<"bad", 0xFF, "x", 0, "y">>))

      assert {:ok, %{status: 400, body: stored}} = Client.post(@url, "{}", @headers)
      assert String.valid?(stored)
      refute String.contains?(stored, <<0>>)
      assert stored == "bad�x�y"
    end
  end
end
