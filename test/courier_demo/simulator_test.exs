defmodule CourierDemo.SimulatorTest do
  use ExUnit.Case, async: true

  alias CourierDemo.Simulator

  @token "ck_simulator-test-token-not-a-secret"
  @merchants ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"]
  @types ["payment.succeeded", "refund.succeeded"]

  # Answers 202 and reports every request to the test process.
  defp stub_api do
    test = self()

    Req.Test.stub(Simulator, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(test, {
        :request,
        %{
          method: conn.method,
          path: conn.request_path,
          authorization: Plug.Conn.get_req_header(conn, "authorization"),
          key: conn |> Plug.Conn.get_req_header("idempotency-key") |> List.first(),
          body: body
        }
      })

      conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{})
    end)
  end

  defp received_requests(acc \\ []) do
    receive do
      {:request, request} -> received_requests([request | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp run(plan, opts \\ []) do
    Simulator.run(
      plan,
      Keyword.merge([token: @token, url: "http://courier.test", rate: 1000], opts)
    )
  end

  describe "Requirement: Event requests" do
    test "Scenario: New events sent" do
      stub_api()

      tally =
        [merchants: @merchants, types: @types, count: 5, repeat_share: 0.0]
        |> Simulator.plan()
        |> run()

      requests = received_requests()
      assert length(requests) == 5
      assert %{new: 5, repeats: 0, rejected: rejected, failed: 0} = tally
      assert rejected == %{}

      for request <- requests do
        assert request.method == "POST"
        assert request.path == "/api/v1/events"
        assert request.authorization == ["Bearer " <> @token]

        assert %{"type" => type, "merchant_id" => merchant_id, "payload" => payload} =
                 Jason.decode!(request.body)

        assert type in @types
        assert merchant_id in @merchants
        assert is_map(payload)
      end

      assert requests |> Enum.map(& &1.key) |> Enum.uniq() |> length() == 5
    end

    test "Scenario: Rate respected" do
      stub_api()

      plan = Simulator.plan(merchants: @merchants, count: 10, repeat_share: 0.0)
      started = System.monotonic_time(:millisecond)
      tally = run(plan, rate: 20)
      elapsed = System.monotonic_time(:millisecond) - started

      assert elapsed >= 450
      assert tally.elapsed_ms >= 450
      assert tally.new == 10
    end
  end

  describe "Requirement: Repeated requests" do
    test "Scenario: Repeats reuse key and body" do
      stub_api()

      # A fixed seed makes the plan the same on every run.
      state = :rand.seed_s(:exsss, {1, 2, 3})
      {:ok, seed} = Agent.start_link(fn -> state end)

      rand = fn -> Agent.get_and_update(seed, &:rand.uniform_s/1) end

      plan = Simulator.plan([merchants: @merchants, count: 20, repeat_share: 0.5], rand)
      assert length(plan) == 20

      # The first request is never a repeat, whatever the random function says.
      always_repeat = Simulator.plan([merchants: @merchants, count: 3, repeat_share: 1.0], rand)
      assert [{key, body}, {key, body}, {key, body}] = always_repeat

      run(plan)
      requests = received_requests()
      assert length(requests) == 20

      bodies_by_key = Enum.group_by(requests, & &1.key, & &1.body)
      assert map_size(bodies_by_key) < 20

      # Every request with a key carries exactly the planned body of that key.
      planned = Map.new(plan)

      for {key, bodies} <- bodies_by_key, body <- bodies do
        assert body == Map.fetch!(planned, key)
      end
    end

    test "Scenario: No repeats" do
      stub_api()

      # Even a random function that always says "repeat" cannot beat a share of 0.
      plan = Simulator.plan([merchants: @merchants, count: 30, repeat_share: 0.0], fn -> 0.0 end)
      run(plan)

      keys = Enum.map(received_requests(), & &1.key)
      assert length(keys) == 30
      assert keys |> Enum.uniq() |> length() == 30
    end
  end
end
