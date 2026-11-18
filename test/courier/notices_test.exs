defmodule Courier.NoticesTest do
  # Not async: PubSub topics and the degraded threshold are global, so
  # notices of concurrent tests would arrive here.
  use Courier.DataCase, async: false
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Delivery
  alias Courier.Delivery.Client
  alias Courier.Delivery.Worker
  alias Courier.Endpoints
  alias Courier.Ingestion
  alias Courier.Merchants
  alias Courier.Notices

  setup do
    for resource <- [:events, :deliveries, :endpoints, :merchants] do
      :ok = Phoenix.PubSub.subscribe(Courier.PubSub, Notices.topic(resource))
    end

    :ok
  end

  defp new_key, do: "key-#{System.unique_integer([:positive])}"

  defp event_attrs(merchant, overrides \\ %{}) do
    Map.merge(
      %{
        "type" => "payment.succeeded",
        "merchant_id" => merchant.id,
        "payload" => %{"amount" => 1000, "currency" => "EUR"}
      },
      overrides
    )
  end

  defp respond(status, body \\ "body") do
    Req.Test.stub(Client, fn conn -> Plug.Conn.send_resp(conn, status, body) end)
  end

  defp attempt(delivery), do: perform_job(Worker, %{delivery_id: delivery.id})

  defp attempt_attrs do
    %{
      started_at: DateTime.utc_now(),
      duration_ms: 5,
      url: "https://hooks.public.test/courier",
      request_headers: %{"webhook-signature" => "[redacted]"},
      response_status: 500,
      response_body: "boom"
    }
  end

  defp with_degraded_threshold(threshold) do
    previous = Application.fetch_env(:courier, :degraded_threshold)
    Application.put_env(:courier, :degraded_threshold, threshold)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:courier, :degraded_threshold, value)
        :error -> Application.delete_env(:courier, :degraded_threshold)
      end
    end)
  end

  # Fixtures announce their own changes; tests start from an empty mailbox.
  defp flush_notices do
    receive do
      {:notice, _name, _payload} -> flush_notices()
    after
      0 -> :ok
    end
  end

  defp delivery_notice(delivery, status) do
    {:notice, "delivery_changed",
     %{
       "id" => delivery.id,
       "event_id" => delivery.event_id,
       "endpoint_id" => delivery.endpoint_id,
       "status" => status
     }}
  end

  defp endpoint_notice(endpoint) do
    {:notice, "endpoint_changed", %{"id" => endpoint.id, "merchant_id" => endpoint.merchant_id}}
  end

  describe "Requirement: Change notices" do
    test "Scenario: Ingestion announced" do
      merchant = merchant_fixture()
      {payments, _} = endpoint_fixture(%{merchant_id: merchant.id, event_types: ["payment.*"]})
      {refunds, _} = endpoint_fixture(%{merchant_id: merchant.id, event_types: ["refund.*"]})
      flush_notices()

      assert {:ok, :created, event} = Ingestion.ingest(event_attrs(merchant), new_key())

      assert_received {:notice, "event_ingested",
                       %{"id" => event_id, "merchant_id" => merchant_id, "type" => type}}

      assert {event_id, merchant_id, type} == {event.id, merchant.id, "payment.succeeded"}

      pending = Enum.find(event.deliveries, &(&1.endpoint_id == payments.id))
      skipped = Enum.find(event.deliveries, &(&1.endpoint_id == refunds.id))
      expected_pending = delivery_notice(pending, "pending")
      expected_skipped = delivery_notice(skipped, "skipped")
      assert_received ^expected_pending
      assert_received ^expected_skipped

      refute_received {:notice, _, _}
    end

    test "Scenario: Delivery outcome announced" do
      delivery = delivery_fixture()
      flush_notices()

      respond(500)
      assert {:snooze, _seconds} = attempt(delivery)
      retry = delivery_notice(delivery, "pending")
      assert_received ^retry

      respond(200)
      assert :ok = attempt(delivery)
      succeeded = delivery_notice(delivery, "succeeded")
      assert_received ^succeeded
      assert Repo.get!(Courier.Delivery.Delivery, delivery.id).status == "succeeded"

      refute_received {:notice, _, _}

      # A failure for good and the end of the retry window (the sweeper's
      # path) are announced the same way.
      failing = delivery_fixture()
      expiring = delivery_fixture()
      flush_notices()

      respond(400)
      assert :ok = attempt(failing)
      failed = delivery_notice(failing, "failed")
      assert_received ^failed

      assert {:ok, %{status: "failed"}} =
               Delivery.fail_without_attempt(expiring.id, DateTime.utc_now())

      window_ended = delivery_notice(expiring, "failed")
      assert_received ^window_ended

      # A stale result changes nothing and announces nothing.
      assert {:ok, :stale} = Delivery.fail_without_attempt(expiring.id, DateTime.utc_now())
      refute_received {:notice, _, _}
    end

    test "Scenario: Resend announced" do
      delivery = delivery_fixture(%{status: "failed"})
      flush_notices()

      assert {:ok, resend} = Delivery.resend(delivery.id, "api_key:ops")

      expected = delivery_notice(resend, "pending")
      assert_received ^expected
      assert resend.id != delivery.id

      # A refused resend (one is already pending) announces nothing.
      assert {:error, :resend_in_progress} = Delivery.resend(delivery.id, "api_key:ops")
      refute_received {:notice, _, _}
    end

    test "Scenario: Endpoint changes announced" do
      with_degraded_threshold(1)
      merchant = merchant_fixture()
      flush_notices()

      {endpoint, _secret} = endpoint_fixture(%{merchant_id: merchant.id})
      expected = endpoint_notice(endpoint)
      assert_received ^expected

      assert {:ok, endpoint} = Endpoints.update_endpoint(endpoint, %{"description" => "Orders"})
      assert_received ^expected

      assert {:ok, endpoint, _secret} = Endpoints.rotate_secret(endpoint)
      assert_received ^expected

      event = event_fixture(%{merchant_id: merchant.id})
      delivery = delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})
      flush_notices()

      at = DateTime.add(DateTime.utc_now(), 60, :second)

      assert {:ok, %{health: :degraded}} =
               Delivery.record_attempt(delivery.id, attempt_attrs(), {:retry_at, at})

      retry = delivery_notice(delivery, "pending")
      assert_received ^retry
      assert_received ^expected

      assert {:ok, %{health: :recovered}} =
               Delivery.record_attempt(
                 delivery.id,
                 %{attempt_attrs() | response_status: 200, response_body: "ok"},
                 {:succeeded, DateTime.utc_now()}
               )

      succeeded = delivery_notice(delivery, "succeeded")
      assert_received ^succeeded
      assert_received ^expected

      # An invalid update is not stored and not announced.
      assert {:error, %Ecto.Changeset{}} = Endpoints.update_endpoint(endpoint, %{"url" => ""})
      refute_received {:notice, _, _}
    end

    test "Scenario: Merchant changes announced" do
      assert {:ok, merchant} = Merchants.create_merchant(%{name: "Acme"})
      assert_received {:notice, "merchant_changed", payload}
      assert payload == %{"id" => merchant.id}

      assert {:ok, _merchant} = Merchants.update_merchant(merchant, %{name: "Acme Inc"})
      assert_received {:notice, "merchant_changed", ^payload}

      assert {:error, %Ecto.Changeset{}} = Merchants.update_merchant(merchant, %{name: ""})
      refute_received {:notice, _, _}
    end

    test "Scenario: Rejected change not announced" do
      merchant = merchant_fixture()
      endpoint_fixture(%{merchant_id: merchant.id})
      flush_notices()

      assert {:error, %Ecto.Changeset{}} =
               Ingestion.ingest(event_attrs(merchant, %{"type" => ""}), new_key())

      refute_received {:notice, _, _}

      key = new_key()
      assert {:ok, :created, _event} = Ingestion.ingest(event_attrs(merchant), key)
      flush_notices()

      assert {:ok, :repeat, _event} = Ingestion.ingest(event_attrs(merchant), key)
      refute_received {:notice, _, _}
    end
  end

  describe "Requirement: Notices carry ids only" do
    test "Scenario: Notice contents" do
      merchant = merchant_fixture()

      event =
        event_fixture(%{
          merchant_id: merchant.id,
          payload: %{"card" => "4242", "secret" => "do-not-send"}
        })

      {endpoint, _secret} = endpoint_fixture(%{merchant_id: merchant.id})
      delivery = delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})
      flush_notices()

      respond(400, "card declined for 4242")
      assert :ok = attempt(delivery)

      assert_received {:notice, "delivery_changed", payload}

      assert payload == %{
               "id" => delivery.id,
               "event_id" => event.id,
               "endpoint_id" => endpoint.id,
               "status" => "failed"
             }

      refute_received {:notice, _, _}
    end
  end
end
