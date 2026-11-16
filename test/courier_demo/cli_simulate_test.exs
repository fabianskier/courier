defmodule CourierDemo.CLISimulateTest do
  # Captures :stderr and sets an environment variable, both global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias CourierDemo.CLI

  @token "ck_cli-simulate-token-not-a-secret"
  @merchant "11111111-1111-4111-8111-111111111111"

  # Reports every request's Authorization header to the test and answers 202.
  defp stub_api do
    test = self()

    Req.Test.stub(CourierDemo.Simulator, fn conn ->
      send(test, {:request, Plug.Conn.get_req_header(conn, "authorization")})
      conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{})
    end)
  end

  # Runs the release entry point and returns {status, stdout, stderr}.
  defp simulate(args) do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        stdout = capture_io(fn -> send(parent, {:status, CLI.simulate(args)}) end)
        send(parent, {:stdout, stdout})
      end)

    assert_received {:status, status}
    assert_received {:stdout, stdout}
    {status, stdout, stderr}
  end

  defp run_args, do: ["--merchant", @merchant, "--url", "http://courier.test", "--rate", "1000"]

  describe "Requirement: Release simulator command" do
    test "Scenario: Release run prints the summary" do
      stub_api()

      args = ["--token", @token, "--count", "3", "--repeat-share", "0"] ++ run_args()
      {status, stdout, stderr} = simulate(args)

      assert status == 0

      for _ <- 1..3, do: assert_received({:request, _authorization})
      refute_received {:request, _authorization}

      assert stdout =~ "Sent 3 requests"
      assert stdout =~ "3 new (202)"
      refute stdout =~ @token
      assert stderr == ""
    end

    test "Scenario: Release run rejects invalid options" do
      stub_api()

      {status, stdout, stderr} = simulate(["--token", @token])

      assert status == 1
      assert stderr =~ "A merchant is required"
      assert stderr =~ "Usage: bin/simulate"
      refute stderr =~ @token
      assert stdout == ""
      refute_received {:request, _authorization}
    end

    test "Scenario: Release run reads the token from the environment" do
      stub_api()

      previous = System.get_env("COURIER_INGEST_TOKEN")
      System.put_env("COURIER_INGEST_TOKEN", @token)

      on_exit(fn ->
        if previous,
          do: System.put_env("COURIER_INGEST_TOKEN", previous),
          else: System.delete_env("COURIER_INGEST_TOKEN")
      end)

      {status, stdout, _stderr} = simulate(["--count", "2", "--repeat-share", "0"] ++ run_args())

      assert status == 0
      assert_received {:request, ["Bearer " <> @token]}
      assert_received {:request, ["Bearer " <> @token]}
      refute stdout =~ @token

      assert {:ok, %{token: "ck_from-env"}} =
               CLI.parse_simulate(["--merchant", @merchant], %{
                 "COURIER_INGEST_TOKEN" => "ck_from-env"
               })

      assert {:error, ["A token is required (--token or COURIER_INGEST_TOKEN)."]} =
               CLI.parse_simulate(["--merchant", @merchant], %{})
    end
  end
end
