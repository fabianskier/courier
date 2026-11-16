defmodule Courier.Delivery.QueueManagerTest do
  # TestQueueControl reports to one registered process at a time.
  use Courier.DataCase, async: false

  import Courier.EndpointsFixtures

  alias Courier.Delivery.QueueManager
  alias Courier.Delivery.Queues
  alias Courier.Delivery.TestQueueControl
  alias Courier.Endpoints

  describe "Requirement: One queue per endpoint" do
    test "Scenario: Queues started at boot" do
      {first, _} = endpoint_fixture()
      {second, _} = endpoint_fixture(%{max_concurrency: 3})
      {disabled, _} = endpoint_fixture()
      {:ok, _} = Endpoints.update_endpoint(disabled, %{enabled: false})

      TestQueueControl.register()
      start_supervised!({QueueManager, name: :"#{__MODULE__}.Boot"})

      first_queue = Queues.name(first.id)
      second_queue = Queues.name(second.id)

      assert_received {:queue_control, :start, ^first_queue, [limit: 10, local_only: true]}
      assert_received {:queue_control, :start, ^second_queue, [limit: 3, local_only: true]}
      refute_received {:queue_control, _, _, _}
    end

    test "Scenario: Queue follows endpoint changes" do
      TestQueueControl.register()

      {endpoint, _} = endpoint_fixture()
      queue = Queues.name(endpoint.id)
      assert_received {:queue_control, :start, ^queue, [limit: 10, local_only: false]}

      {:ok, endpoint} = Endpoints.update_endpoint(endpoint, %{max_concurrency: 5})
      assert_received {:queue_control, :scale, ^queue, 5}

      {:ok, _} = Endpoints.update_endpoint(endpoint, %{enabled: false})
      assert_received {:queue_control, :stop, ^queue, nil}

      refute_received {:queue_control, _, _, _}
    end

    test "an update that changes neither enabled nor max_concurrency sends no signal" do
      {endpoint, _} = endpoint_fixture()
      TestQueueControl.register()

      {:ok, _} = Endpoints.update_endpoint(endpoint, %{description: "renamed"})

      refute_received {:queue_control, _, _, _}
    end

    test "re-enabling a disabled endpoint starts its queue again" do
      {endpoint, _} = endpoint_fixture()
      {:ok, endpoint} = Endpoints.update_endpoint(endpoint, %{enabled: false})
      TestQueueControl.register()

      {:ok, _} = Endpoints.update_endpoint(endpoint, %{enabled: true})

      queue = Queues.name(endpoint.id)
      assert_received {:queue_control, :start, ^queue, [limit: 10, local_only: false]}
    end
  end

  describe "Queues.name/1" do
    test "prefixes the endpoint id" do
      assert Queues.name("abc") == "endpoint:abc"
    end
  end
end
