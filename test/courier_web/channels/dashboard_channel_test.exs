defmodule CourierWeb.DashboardChannelTest do
  # Not async: PubSub notice topics are global, so notices of concurrent
  # tests would reach these channels.
  use CourierWeb.ChannelCase, async: false

  import Courier.AccessFixtures
  import Courier.AuditFixtures
  import Courier.MerchantsFixtures

  alias Courier.Delivery
  alias Courier.Merchants
  alias CourierWeb.DashboardChannel
  alias CourierWeb.DashboardSocket

  setup do
    %{token: token} = api_key_fixture(%{scopes: ["read"]})
    {:ok, socket} = connect(DashboardSocket, %{}, connect_info: %{auth_token: token})
    %{socket: socket}
  end

  describe "Requirement: Dashboard topics" do
    test "Scenario: Notice pushed to its topic", %{socket: socket} do
      for topic <-
            ~w(dashboard:events dashboard:deliveries dashboard:endpoints dashboard:merchants) do
        assert {:ok, _reply, _channel} = subscribe_and_join(socket, DashboardChannel, topic)
      end

      delivery = delivery_fixture()

      assert {:ok, %{status: "failed"}} =
               Delivery.fail_without_attempt(delivery.id, DateTime.utc_now())

      assert_push "delivery_changed", %{"id" => id, "status" => "failed"}
      assert id == delivery.id

      # Each notice goes only to the topic of its resource.
      merchant = merchant_fixture()
      merchant_id = merchant.id
      {:ok, _} = Merchants.update_merchant(merchant, %{"name" => "Renamed"})

      assert_receive %Phoenix.Socket.Message{
        topic: "dashboard:merchants",
        event: "merchant_changed",
        payload: %{"id" => ^merchant_id}
      }

      for topic <- ~w(dashboard:events dashboard:deliveries dashboard:endpoints) do
        refute_received %Phoenix.Socket.Message{topic: ^topic, event: "merchant_changed"}
      end

      for topic <- ~w(dashboard:events dashboard:endpoints dashboard:merchants) do
        refute_received %Phoenix.Socket.Message{topic: ^topic, event: "delivery_changed"}
      end
    end

    test "Scenario: Unknown topic refused", %{socket: socket} do
      assert {:error, %{reason: "unknown topic"}} =
               subscribe_and_join(socket, DashboardChannel, "dashboard:api_keys")
    end
  end
end
