defmodule Mix.Tasks.Courier.SimulateTest do
  # Mix.shell/1 is global, so these tests cannot run concurrently.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Courier.Simulate

  @token "ck_simulate-task-token-not-a-secret"
  @merchant "11111111-1111-4111-8111-111111111111"

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp collect_output(acc \\ []) do
    receive do
      {:mix_shell, kind, [line]} when kind in [:info, :error] ->
        collect_output([{kind, line} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp text(output, kind) do
    Enum.join(for({^kind, line} <- output, do: line), "\n")
  end

  # Reports every request to the test process and answers with `respond`.
  defp stub_api(respond) do
    test = self()

    Req.Test.stub(CourierDemo.Simulator, fn conn ->
      [key] = Plug.Conn.get_req_header(conn, "idempotency-key")
      send(test, {:request, key})
      respond.(conn, key)
    end)
  end

  defp status(conn, status), do: conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})

  describe "Requirement: Simulator options" do
    test "Scenario: Missing merchant" do
      stub_api(fn conn, _key -> status(conn, 202) end)

      assert catch_exit(Simulate.run(["--token", @token])) == {:shutdown, 1}

      output = collect_output()
      assert text(output, :error) =~ "A merchant is required"
      refute text(output, :error) =~ @token
      refute_received {:request, _key}
    end

    test "Scenario: Invalid rate" do
      stub_api(fn conn, _key -> status(conn, 202) end)

      assert catch_exit(Simulate.run(["--token", @token, "--merchant", @merchant, "--rate", "0"])) ==
               {:shutdown, 1}

      assert collect_output() |> text(:error) =~ "The rate must be between 1 and 1000"
      refute_received {:request, _key}
    end
  end

  describe "Requirement: Run summary" do
    test "Scenario: Summary printed" do
      # With no repeats, keys end in the request's index: answer by index.
      stub_api(fn conn, key ->
        case key |> String.split("-") |> List.last() do
          index when index in ["0", "1", "2"] -> status(conn, 202)
          "3" -> status(conn, 200)
          "4" -> status(conn, 422)
          "5" -> Req.Test.transport_error(conn, :econnrefused)
        end
      end)

      args =
        ["--token", @token, "--merchant", @merchant, "--url", "http://courier.test"] ++
          ["--count", "6", "--rate", "1000", "--repeat-share", "0"]

      assert Simulate.run(args) == :ok

      output = collect_output()
      info = text(output, :info)

      assert info =~ "Sent 6 requests"
      assert info =~ "3 new (202)"
      assert info =~ "1 repeat (200)"
      assert info =~ "1 rejected with status 422"
      assert info =~ "1 failed (no response)"
      refute info =~ @token
      assert text(output, :error) == ""
    end
  end
end
