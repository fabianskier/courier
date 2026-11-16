defmodule CourierDemo.CLISeedTest do
  # Not async: sets an environment variable.
  use Courier.DataCase, async: false

  import ExUnit.CaptureIO

  alias Courier.Access.ApiKey
  alias Courier.Endpoints.Endpoint
  alias Courier.Merchants.Merchant
  alias CourierDemo.{CLI, Seeds}

  @receiver_url "https://receiver.public.test"

  setup do
    previous = System.get_env("COURIER_DEMO_RECEIVER_URL")
    System.put_env("COURIER_DEMO_RECEIVER_URL", @receiver_url)

    on_exit(fn ->
      if previous,
        do: System.put_env("COURIER_DEMO_RECEIVER_URL", previous),
        else: System.delete_env("COURIER_DEMO_RECEIVER_URL")
    end)
  end

  # Plays a reachable receiver: answers 204 and reports every request to the test.
  defp stub_receiver do
    test = self()

    Req.Test.stub(Seeds, fn conn ->
      send(test, {:registration, conn.host, conn.request_path})
      Plug.Conn.send_resp(conn, 204, "")
    end)
  end

  defp stub_unreachable_receiver do
    Req.Test.stub(Seeds, &Req.Test.transport_error(&1, :econnrefused))
  end

  # Runs the release entry point and returns what it prints.
  defp seed, do: capture_io(fn -> assert CLI.seed() == :ok end)

  defp stored do
    {Repo.all(ApiKey), Repo.all(Merchant), Repo.all(Endpoint)}
  end

  describe "Requirement: Release seeding output" do
    test "Scenario: Release output ready to use" do
      stub_receiver()

      output = seed()

      for _ <- 1..5, do: assert_received({:registration, "receiver.public.test", _path})

      assert [token | _] = Regex.run(~r/ck_\S+/, output)
      assert {:ok, %ApiKey{name: "demo"}} = Courier.Access.authenticate(token)
      assert [_, _, _] = merchants = Repo.all(Merchant)

      for merchant <- merchants do
        assert output =~ merchant.id
        assert output =~ merchant.name
      end

      [command] = Regex.run(~r/docker compose exec courier bin\/simulate .*/, output)
      for merchant <- merchants, do: assert(command =~ "--merchant #{merchant.id}")
      assert command =~ "--token #{token}"

      refute output =~ "mix "
      refute output =~ "WARNING"
      refute output =~ "whsec_"
    end

    test "Scenario: Release second run refused" do
      stub_receiver()
      assert seed() =~ "Demo data created."
      for _ <- 1..5, do: assert_received({:registration, _host, _path})

      before = stored()
      assert {[_key], [_, _, _], [_, _, _, _, _]} = before

      output = seed()

      assert stored() == before
      refute_received {:registration, _host, _path}

      assert output =~ "already seeded"
      assert output =~ "docker compose down -v"
      assert output =~ "docker compose exec courier bin/seed"
      refute output =~ "mix ecto.reset"
      refute output =~ "mix"
    end
  end

  describe "Requirement: Release seeding command" do
    test "Scenario: Release receiver unreachable" do
      stub_unreachable_receiver()

      output = seed()

      assert {[_key], [_, _, _], [_, _, _, _, _] = endpoints} = stored()

      assert output =~ "WARNING"
      assert output =~ "unchecked"
      for endpoint <- endpoints, do: assert(output =~ endpoint.description)
      assert output =~ "docker compose up -d demo-receiver"
      assert output =~ "docker compose exec courier bin/simulate"
      refute output =~ "whsec_"
      refute output =~ "mix"
    end
  end
end
