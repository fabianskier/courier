defmodule Courier.Delivery.ResendWorkerTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Audit
  alias Courier.Delivery
  alias Courier.Delivery.Client
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.Worker

  defp header(headers, name) do
    {^name, value} = List.keyfind(headers, name, 0)
    value
  end

  describe "Requirement: Resends keep the webhook id" do
    test "Scenario: Same webhook id" do
      {endpoint, _secret} = endpoint_fixture()
      event = event_fixture(%{merchant_id: endpoint.merchant_id})

      failed =
        delivery_fixture(%{
          endpoint_id: endpoint.id,
          event_id: event.id,
          status: "failed",
          completed_at: DateTime.utc_now()
        })

      assert {:ok, resend} = Delivery.resend(failed.id, "api_key:ops")
      assert [job] = all_enqueued(worker: Worker)

      test_pid = self()

      Req.Test.stub(Client, fn conn ->
        send(test_pid, {:request, conn.req_headers})
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      assert :ok = perform_job(Worker, job.args)

      assert_received {:request, headers}
      assert header(headers, "webhook-id") == event.id
      assert header(headers, "courier-delivery-id") == resend.id
      refute_received {:request, _headers}

      assert Repo.get!(DeliveryRecord, resend.id).status == "succeeded"
      assert [%{number: 1, response_status: 200}] = Audit.list_attempts(resend.id)

      # The resent delivery is untouched by the resend's attempt.
      assert Repo.get!(DeliveryRecord, failed.id).status == "failed"
      assert Audit.list_attempts(failed.id) == []
    end
  end
end
