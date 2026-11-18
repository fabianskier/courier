defmodule CourierDemo.LoadTest do
  # Captures :stderr and changes an environment variable, both global.
  use Courier.DataCase, async: false

  import ExUnit.CaptureIO
  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Delivery.Delivery
  alias CourierDemo.{CLI, Load}

  @token "ck_load-test-token-not-a-secret"
  @t0 ~U[2026-01-01 12:00:00.000000Z]

  setup do
    previous = System.get_env("COURIER_INGEST_TOKEN")
    System.delete_env("COURIER_INGEST_TOKEN")

    on_exit(fn ->
      if previous, do: System.put_env("COURIER_INGEST_TOKEN", previous)
    end)
  end

  # Reports every request to the test and answers 202.
  defp stub_api do
    test = self()

    Req.Test.stub(CourierDemo.Simulator, fn conn ->
      send(test, :request)
      conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{})
    end)
  end

  # Runs the release entry point and returns {status, stdout, stderr}.
  defp load(args) do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        stdout = capture_io(fn -> send(parent, {:status, CLI.load(args)}) end)
        send(parent, {:stdout, stdout})
      end)

    assert_received {:status, status}
    assert_received {:stdout, stdout}
    {status, stdout, stderr}
  end

  defp received_requests(n \\ 0) do
    receive do
      :request -> received_requests(n + 1)
    after
      0 -> n
    end
  end

  # A delivery to `endpoint` created at `inserted_at`, with a first attempt
  # `after_ms` later, or none when `after_ms` is nil.
  defp delivery_at(endpoint, inserted_at, after_ms) do
    event = event_fixture(%{merchant_id: endpoint.merchant_id})
    delivery = delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})

    Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id),
      set: [inserted_at: inserted_at]
    )

    if after_ms do
      attempt_fixture(%{
        delivery_id: delivery.id,
        started_at: DateTime.add(inserted_at, after_ms, :millisecond),
        url: endpoint.url
      })
    end

    delivery
  end

  defp window(merchant_id) do
    %{merchants: [merchant_id], from: DateTime.add(@t0, -1), to: DateTime.add(@t0, 1)}
  end

  defp report(window, waited_s \\ 0) do
    Load.delivery_report(Load.delivery_rows(window), %{
      waited_s: waited_s,
      attempts_per_second: 10.0
    })
  end

  describe "Requirement: Load options" do
    test "Scenario: Missing token" do
      stub_api()
      merchant = Ecto.UUID.generate()

      assert {:error, [message]} = Load.parse(["--merchant", merchant], %{})
      assert message =~ "token"

      {status, stdout, stderr} = load(["--merchant", merchant, "--url", "http://courier.test"])

      assert status == 1
      assert stderr =~ "A token is required"
      assert stderr =~ "Usage: bin/load"
      assert stdout == ""
      assert received_requests() == 0
    end

    test "Scenario: Invalid rate" do
      stub_api()
      args = ["--token", @token, "--merchant", Ecto.UUID.generate(), "--rate", "0"]

      {status, stdout, stderr} = load(args ++ ["--url", "http://courier.test"])

      assert status == 1
      assert stderr =~ "--rate"
      refute stderr =~ @token
      assert stdout == ""
      assert received_requests() == 0

      for option <- ["--count", "--wait"] do
        assert {:error, [message]} =
                 Load.parse(["--token", @token, "--merchant", Ecto.UUID.generate(), option, "-1"])

        assert message =~ option
      end
    end

    test "Scenario: Defaults" do
      merchant = Ecto.UUID.generate()

      assert {:ok, config} =
               Load.parse(["--merchant", merchant], %{"COURIER_INGEST_TOKEN" => @token})

      assert config == %{
               merchants: [merchant],
               token: @token,
               url: "http://localhost:4000",
               rate: 50,
               count: 500,
               wait: 30
             }
    end
  end

  describe "Requirement: Ingestion report" do
    test "Scenario: Ingestion measured" do
      stub_api()

      args = [
        "--token",
        @token,
        "--merchant",
        Ecto.UUID.generate(),
        "--url",
        "http://courier.test"
      ]

      {status, stdout, stderr} = load(args ++ ["--count", "100", "--rate", "50", "--wait", "1"])

      assert status == 0
      assert stderr == ""
      assert received_requests() == 100
      assert stdout =~ ~r/Ingestion: 100 sent in \d+\.\d s \(\d+\.\d\/s\): 100 x 202, 0 failed/
      assert stdout =~ ~r/latency p50 \d+ ms, p95 \d+ ms, p99 \d+ ms/
      refute stdout =~ @token
    end
  end

  describe "Requirement: Delivery report" do
    test "Scenario: Time to first attempt" do
      {endpoint, _secret} = endpoint_fixture()
      for ms <- [300, 100, 200], do: delivery_at(endpoint, @t0, ms)

      assert [summary, times, attempts | _endpoints] = report(window(endpoint.merchant_id))

      assert summary == "Delivery: 3 deliveries, 0 without an attempt yet after 0 s"
      assert times == "  time to first attempt p50 200 ms, p95 300 ms"
      assert attempts == "  attempts 10.0/s"
    end

    test "Scenario: Per endpoint" do
      {fast, _secret} = endpoint_fixture(%{url: "https://fast.public.test/hooks"})

      {slow, _secret} =
        endpoint_fixture(%{merchant_id: fast.merchant_id, url: "https://slow.public.test/hooks"})

      for ms <- [10, 20], do: delivery_at(fast, @t0, ms)
      for ms <- [5000, 6000, 7000], do: delivery_at(slow, @t0, ms)

      # Outside the run: another merchant, before the window, skipped.
      {other, _secret} = endpoint_fixture()
      delivery_at(other, @t0, 1)
      delivery_at(fast, DateTime.add(@t0, -60), 1)
      skipped = delivery_at(fast, @t0, nil)
      Repo.update_all(from(d in Delivery, where: d.id == ^skipped.id), set: [status: "skipped"])

      lines = report(window(fast.merchant_id))

      assert "Delivery: 5 deliveries, 0 without an attempt yet after 0 s" in lines

      assert "  https://fast.public.test/hooks  2 deliveries, 2 attempts  p50 10 ms, p95 20 ms" in lines

      assert "  https://slow.public.test/hooks  3 deliveries, 3 attempts  p50 6000 ms, p95 7000 ms" in lines

      assert Load.count_attempts(DateTime.add(@t0, -1), DateTime.add(@t0, 10)) == 6
    end

    test "Scenario: Deliveries without attempts" do
      {endpoint, _secret} = endpoint_fixture()
      for _ <- 1..4, do: delivery_at(endpoint, @t0, nil)
      for ms <- [100, 300], do: delivery_at(endpoint, @t0, ms)

      window = window(endpoint.merchant_id)
      test = self()

      assert Load.count_without_attempt(window) == 4
      assert Load.wait_for_first_attempts(window, 3, &send(test, {:slept, &1})) == 3
      for _ <- 1..3, do: assert_received({:slept, 1000})
      refute_received {:slept, _ms}

      assert [summary, times | _endpoints] = report(window, 3)
      assert summary == "Delivery: 6 deliveries, 4 without an attempt yet after 3 s"
      assert times == "  time to first attempt p50 100 ms, p95 300 ms"
    end

    test "Scenario: Waiting stops when every delivery has an attempt" do
      {endpoint, _secret} = endpoint_fixture()
      delivery_at(endpoint, @t0, 100)

      assert Load.wait_for_first_attempts(window(endpoint.merchant_id), 30, fn _ms ->
               flunk("should not wait")
             end) == 0
    end
  end

  describe "Requirement: Release load command" do
    test "Scenario: Load from the release" do
      script = Path.expand("../../rel/overlays/bin/load", __DIR__)

      assert File.exists?(script)
      assert Bitwise.band(File.stat!(script).mode, 0o111) != 0
      assert File.read!(script) =~ "CourierDemo.CLI.load(System.argv())"

      stub_api()

      args = [
        "--token",
        @token,
        "--merchant",
        Ecto.UUID.generate(),
        "--url",
        "http://courier.test"
      ]

      {status, stdout, _stderr} = load(args ++ ["--count", "3", "--rate", "1000"])

      assert status == 0
      assert received_requests() == 3
      assert stdout =~ "Ingestion: 3 sent"
      assert stdout =~ "Delivery: 0 deliveries, 0 without an attempt yet"
    end
  end
end
