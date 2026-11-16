defmodule Courier.Delivery.WorkerRetryTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Audit
  alias Courier.Delivery.Client
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.Worker

  # The largest backoff after attempt n without Retry-After: 1 + min(3600, 10 * 2^(n-1)).
  @max_backoff_after_1 11
  @max_backoff_after_2 21

  defp setup_delivery(endpoint_attrs \\ %{}) do
    {endpoint, _secret} = endpoint_fixture(endpoint_attrs)
    event = event_fixture(%{merchant_id: endpoint.merchant_id})
    delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})
  end

  defp reload(delivery), do: Repo.get!(DeliveryRecord, delivery.id)

  # Runs the job and returns its result with the wall-clock bounds of the run,
  # so a snooze can be compared with the stored `next_attempt_at`.
  defp run(delivery) do
    before = DateTime.utc_now()
    result = perform_job(Worker, %{delivery_id: delivery.id})
    {result, before, DateTime.utc_now()}
  end

  defp stub_response(status, body, headers \\ []) do
    test_pid = self()

    Req.Test.stub(Client, fn conn ->
      send(test_pid, :request)

      headers
      |> Enum.reduce(conn, fn {name, value}, conn ->
        Plug.Conn.put_resp_header(conn, name, value)
      end)
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  # `next_attempt_at` is `delay` seconds after the moment the response came
  # back, which lies between the start and the end of the run.
  defp assert_scheduled(stored, seconds, before, finished) do
    assert %DateTime{} = at = stored.next_attempt_at
    assert DateTime.compare(at, DateTime.add(before, seconds, :second)) != :lt
    assert DateTime.compare(at, DateTime.add(finished, seconds, :second)) != :gt
  end

  defp assert_pending_retry(delivery, seconds, before, finished) do
    stored = reload(delivery)
    assert stored.status == "pending"
    assert stored.completed_at == nil
    assert_scheduled(stored, seconds, before, finished)
    stored
  end

  describe "Requirement: Retryable failures are retried" do
    test "Scenario: Server error" do
      delivery = setup_delivery()
      stub_response(503, "unavailable")

      assert {{:snooze, first}, before, finished} = run(delivery)
      assert_received :request
      assert first in 1..@max_backoff_after_1

      stored = assert_pending_retry(delivery, first, before, finished)
      assert stored.attempt_count == 1

      assert [%{number: 1, response_status: 503, response_body: "unavailable", error: nil}] =
               Audit.list_attempts(delivery.id)

      # The snoozed job runs again: a second attempt, with the next backoff step.
      assert {{:snooze, second}, before, finished} = run(delivery)
      assert second in 1..@max_backoff_after_2

      stored = assert_pending_retry(delivery, second, before, finished)
      assert stored.attempt_count == 2

      assert [%{number: 1, response_status: 503}, %{number: 2, response_status: 503}] =
               Audit.list_attempts(delivery.id)
    end

    test "Scenario: Timeout" do
      delivery = setup_delivery()
      Req.Test.stub(Client, &Req.Test.transport_error(&1, :timeout))

      assert {{:snooze, seconds}, before, finished} = run(delivery)
      assert seconds in 1..@max_backoff_after_1

      stored = assert_pending_retry(delivery, seconds, before, finished)
      assert stored.attempt_count == 1

      assert [attempt] = Audit.list_attempts(delivery.id)
      assert attempt.number == 1
      assert attempt.response_status == nil
      assert attempt.response_body == nil
      assert attempt.error == "timeout"
      assert attempt.request_headers["webhook-signature"] == "[redacted]"
    end

    test "Scenario: 4xx retried when configured" do
      delivery = setup_delivery(%{retry_on_4xx: true})
      stub_response(404, "not found")

      assert {{:snooze, seconds}, before, finished} = run(delivery)
      assert seconds in 1..@max_backoff_after_1

      stored = assert_pending_retry(delivery, seconds, before, finished)
      assert stored.attempt_count == 1
      assert [%{number: 1, response_status: 404}] = Audit.list_attempts(delivery.id)
    end
  end

  describe "Requirement: Backoff with jitter and Retry-After" do
    test "Scenario: Retry-After honoured" do
      delivery = setup_delivery()
      stub_response(429, "slow down", [{"retry-after", "120"}])

      assert {{:snooze, seconds}, before, finished} = run(delivery)
      # Retry-After asks for longer than any first backoff (at most 11 s).
      assert seconds == 120

      assert_pending_retry(delivery, 120, before, finished)
      assert [%{number: 1, response_status: 429}] = Audit.list_attempts(delivery.id)
    end

    test "Scenario: Retry-After capped" do
      delivery = setup_delivery()
      stub_response(503, "maintenance", [{"retry-after", "86400"}])

      assert {{:snooze, seconds}, before, finished} = run(delivery)
      assert seconds == 3600

      stored = assert_pending_retry(delivery, 3600, before, finished)
      assert DateTime.diff(stored.next_attempt_at, before, :second) <= 3600
      assert [%{number: 1, response_status: 503}] = Audit.list_attempts(delivery.id)
    end

    test "Retry-After is ignored on a 500" do
      delivery = setup_delivery()
      stub_response(500, "boom", [{"retry-after", "3000"}])

      assert {{:snooze, seconds}, before, finished} = run(delivery)
      assert seconds in 1..@max_backoff_after_1

      assert_pending_retry(delivery, seconds, before, finished)
    end
  end

  describe "Requirement: Retry window ends retries" do
    test "Scenario: Window ends after a failure" do
      delivery = setup_delivery()
      stub_response(500, "boom")

      # Every delay is at least 1 second, so any next attempt computed after
      # this point starts at or after the window end.
      window_ends_at = DateTime.add(DateTime.utc_now(), 1, :second)

      {1, _} =
        Repo.update_all(where(DeliveryRecord, id: ^delivery.id),
          set: [window_ends_at: window_ends_at]
        )

      assert {:ok, _before, _finished} = run(delivery)
      assert_received :request

      stored = reload(delivery)
      assert stored.status == "failed"
      assert %DateTime{} = stored.completed_at
      assert stored.next_attempt_at == nil
      assert stored.attempt_count == 1
      assert [%{number: 1, response_status: 500}] = Audit.list_attempts(delivery.id)
    end
  end
end
