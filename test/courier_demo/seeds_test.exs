defmodule CourierDemo.SeedsTest do
  # Not async: one scenario sets an environment variable.
  use Courier.DataCase, async: false

  alias Courier.Access.ApiKey
  alias Courier.Endpoints
  alias Courier.Endpoints.Endpoint
  alias Courier.Merchants.Merchant
  alias CourierDemo.Seeds

  @receiver_url "https://receiver.public.test"

  # Plays a reachable receiver: answers 204 and reports every request to the test.
  defp stub_receiver do
    test = self()

    Req.Test.stub(Seeds, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:registration, conn.method, conn.host, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 204, "")
    end)
  end

  defp stub_unreachable_receiver do
    Req.Test.stub(Seeds, &Req.Test.transport_error(&1, :econnrefused))
  end

  defp seed(opts \\ [receiver_url: @receiver_url]), do: Seeds.run(opts)

  defp stored do
    {Repo.all(ApiKey), Repo.all(Merchant), Repo.all(Endpoint)}
  end

  defp endpoints_by_name do
    Endpoint |> Repo.all() |> Map.new(&{&1.description, &1})
  end

  describe "Requirement: Demo data set" do
    test "Scenario: Data created" do
      stub_receiver()

      assert {:ok, summary} = seed()

      assert [%ApiKey{name: "demo", scopes: scopes, revoked_at: nil}] = Repo.all(ApiKey)
      assert Enum.sort(scopes) == ["ingest", "read", "write"]
      assert {:ok, %ApiKey{name: "demo"}} = Courier.Access.authenticate(summary.token)

      merchants = Repo.all(Merchant)

      assert merchants |> Enum.map(& &1.name) |> Enum.sort() ==
               ["Harbor Outfitters", "Pine Hardware", "Sunrise Bakery"]

      merchant_names = Map.new(merchants, &{&1.id, &1.name})
      endpoints = endpoints_by_name()
      assert map_size(endpoints) == 5
      assert Enum.all?(Map.values(endpoints), & &1.enabled)

      for {name, behaviour, merchant} <- [
            {"sunrise-ok", "ok", "Sunrise Bakery"},
            {"harbor-fail", "fail", "Harbor Outfitters"},
            {"harbor-rate-limit", "rate-limit", "Harbor Outfitters"},
            {"pine-bad-request", "bad-request", "Pine Hardware"},
            {"pine-timeout", "timeout", "Pine Hardware"}
          ] do
        endpoint = Map.fetch!(endpoints, name)
        assert endpoint.url == "#{@receiver_url}/hooks/#{name}/#{behaviour}"
        assert Map.fetch!(merchant_names, endpoint.merchant_id) == merchant
      end

      assert endpoints["sunrise-ok"].event_types == ["payment.*"]
      assert endpoints["harbor-fail"].retry_window_seconds == 300
      assert endpoints["pine-timeout"].max_concurrency == 2

      # The others keep the defaults.
      assert endpoints["harbor-rate-limit"].event_types == []
      assert endpoints["harbor-rate-limit"].retry_window_seconds == 86_400
      assert endpoints["pine-bad-request"].max_concurrency == 10
    end
  end

  describe "Requirement: Receiver URL" do
    test "Scenario: Receiver URL from the environment" do
      stub_receiver()
      previous = System.get_env("COURIER_DEMO_RECEIVER_URL")
      System.put_env("COURIER_DEMO_RECEIVER_URL", @receiver_url)

      on_exit(fn ->
        if previous,
          do: System.put_env("COURIER_DEMO_RECEIVER_URL", previous),
          else: System.delete_env("COURIER_DEMO_RECEIVER_URL")
      end)

      assert {:ok, summary} = seed([])

      urls = Endpoint |> Repo.all() |> Enum.map(& &1.url)
      assert length(urls) == 5
      assert Enum.all?(urls, &String.starts_with?(&1, "#{@receiver_url}/hooks/"))
      assert summary.receiver_url == @receiver_url

      # The registrations go to the same receiver.
      for _ <- 1..5, do: assert_received({:registration, "PUT", "receiver.public.test", _, _})
    end
  end

  describe "Requirement: Secrets registered with the receiver" do
    test "Scenario: Secrets registered" do
      stub_receiver()

      assert {:ok, summary} = seed()
      assert Enum.all?(summary.endpoints, & &1.registered)

      endpoints = endpoints_by_name()

      for name <- Map.keys(endpoints) do
        path = "/_secrets/#{name}"
        assert_received {:registration, "PUT", "receiver.public.test", ^path, body}
        assert body == %{"secret" => hd(Endpoints.signing_secrets(Map.fetch!(endpoints, name)))}
        assert "whsec_" <> _ = body["secret"]
      end

      # One registration per endpoint, no more.
      refute_received {:registration, _, _, _, _}
    end

    test "Scenario: Receiver unreachable" do
      stub_unreachable_receiver()

      assert {:ok, summary} = result = seed()
      assert {[_key], [_, _, _], [_, _, _, _, _]} = stored()
      assert Enum.all?(summary.endpoints, &(&1.registered == false))

      output = Seeds.report(result)
      assert output =~ "WARNING"
      assert output =~ "unchecked"
      for endpoint <- summary.endpoints, do: assert(output =~ endpoint.name)
      refute output =~ "whsec_"
      refute inspect(summary) =~ "whsec_"
    end
  end

  describe "Requirement: Seeding output" do
    test "Scenario: Output ready to use" do
      stub_receiver()

      assert {:ok, summary} = result = seed()
      output = Seeds.report(result)

      assert "ck_" <> _ = summary.token
      assert output =~ summary.token
      assert [_, _, _] = merchants = Repo.all(Merchant)

      for merchant <- merchants do
        assert output =~ merchant.id
        assert output =~ merchant.name
      end

      [command] = Regex.run(~r/mix courier\.simulate .*/, output)
      for merchant <- merchants, do: assert(command =~ "--merchant #{merchant.id}")
      assert command =~ "--token #{summary.token}"

      refute output =~ "WARNING"
      refute output =~ "whsec_"
    end
  end

  describe "Requirement: Seed once" do
    test "Scenario: Second run refused" do
      stub_receiver()
      assert {:ok, _summary} = seed()
      for _ <- 1..5, do: assert_received({:registration, _, _, _, _})

      before = stored()

      assert {:error, :already_seeded} = result = seed()

      assert stored() == before
      refute_received {:registration, _, _, _, _}

      output = Seeds.report(result)
      assert output =~ "already seeded"
      assert output =~ "mix ecto.reset"
    end
  end
end
