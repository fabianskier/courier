defmodule CourierDemo.ReceiverDeliveryTest do
  # A real HTTP server, application config overrides and the global log
  # level: nothing else may run meanwhile.
  use Courier.DataCase, async: false
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures
  import CourierWeb.LogCapture

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Client
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.Worker
  alias Courier.Endpoints.URLPolicy

  setup do
    # Loopback over plain http is allowed, and requests go through Finch to
    # the real receiver instead of Req.Test stubs.
    override_env(URLPolicy,
      require_https: false,
      allowed_hosts: ["127.0.0.1"],
      resolver: Courier.Endpoints.TestResolver
    )

    override_env(Client, [])

    supervisor =
      start_supervised!(
        {CourierDemo.Receiver, port: 0, secrets: Module.concat(__MODULE__, Secrets)}
      )

    {:server, server, _type, _modules} =
      supervisor |> Supervisor.which_children() |> List.keyfind(:server, 0)

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    %{base_url: "http://127.0.0.1:#{port}"}
  end

  defp override_env(key, value) do
    previous = Application.fetch_env(:courier, key)
    Application.put_env(:courier, key, value)

    on_exit(fn ->
      case previous do
        {:ok, old} -> Application.put_env(:courier, key, old)
        :error -> Application.delete_env(:courier, key)
      end
    end)
  end

  describe "Requirement: Signature verification" do
    test "Scenario: Valid signature accepted", %{base_url: base_url} do
      {endpoint, secret} = endpoint_fixture(%{url: base_url <> "/hooks/shop/ok"})
      event = event_fixture(%{merchant_id: endpoint.merchant_id})
      delivery = delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})

      assert Req.put!(base_url <> "/_secrets/shop", json: %{secret: secret}, retry: false).status ==
               204

      {result, log} =
        capture_debug_log(fn -> perform_job(Worker, %{delivery_id: delivery.id}) end)

      assert result == :ok

      # The receiver checked the signature (it was not an unchecked request).
      assert log =~ "demo-receiver name=shop behaviour=ok signature=valid"
      assert log =~ "courier-delivery-id=#{delivery.id}"

      assert [%Attempt{number: 1, response_status: 200, response_body: "ok", error: nil}] =
               Repo.all(from a in Attempt, where: a.delivery_id == ^delivery.id)

      assert %DeliveryRecord{status: "succeeded", attempt_count: 1} =
               Repo.get!(DeliveryRecord, delivery.id)
    end
  end
end
