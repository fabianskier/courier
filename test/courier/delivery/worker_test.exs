defmodule Courier.Delivery.WorkerTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Audit
  alias Courier.Delivery.Client
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.Worker
  alias Courier.Endpoints.Endpoint

  defp setup_delivery(endpoint_attrs \\ %{}) do
    {endpoint, secret} = endpoint_fixture(endpoint_attrs)
    event = event_fixture(%{merchant_id: endpoint.merchant_id})
    delivery = delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})
    %{endpoint: endpoint, secret: secret, event: event, delivery: delivery}
  end

  defp run(delivery), do: perform_job(Worker, %{delivery_id: delivery.id})

  defp reload(delivery), do: Repo.get!(DeliveryRecord, delivery.id)

  # Answers every request with `status` and `body`, and sends what it got to
  # the test process.
  defp stub_response(status, body \\ "ok") do
    test_pid = self()

    Req.Test.stub(Client, fn conn ->
      {:ok, req_body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:request, conn.method, conn.host, conn.request_path, conn.req_headers, req_body}
      )

      Plug.Conn.send_resp(conn, status, body)
    end)
  end

  # Verifies one `v1,` signature the way a receiver would.
  defp valid_signature?("whsec_" <> encoded, signature, headers, body) do
    id = header(headers, "webhook-id")
    ts = header(headers, "webhook-timestamp")
    key = Base.decode64!(encoded)
    expected = Base.encode64(:crypto.mac(:hmac, :sha256, key, "#{id}.#{ts}.#{body}"))
    Plug.Crypto.secure_compare(signature, expected)
  end

  defp header(headers, name) do
    {^name, value} = List.keyfind(headers, name, 0)
    value
  end

  defp signatures(headers) do
    headers
    |> header("webhook-signature")
    |> String.split(" ")
    |> Enum.map(fn "v1," <> sig -> sig end)
  end

  describe "Requirement: Signed webhook requests" do
    test "Scenario: Request headers and body" do
      %{endpoint: endpoint, secret: secret, event: event, delivery: delivery} = setup_delivery()
      test_pid = self()

      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [signature] = signatures(conn.req_headers)
        send(test_pid, {:verified, valid_signature?(secret, signature, conn.req_headers, body)})

        send(
          test_pid,
          {:request, conn.method, conn.host, conn.request_path, conn.req_headers, body}
        )

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      assert :ok = run(delivery)

      assert_received {:verified, true}
      assert_received {:request, "POST", "hooks.public.test", "/courier", headers, body}
      assert endpoint.url == "https://hooks.public.test/courier"

      assert header(headers, "webhook-id") == event.id
      assert header(headers, "courier-delivery-id") == delivery.id
      assert header(headers, "content-type") == "application/json"
      assert "courier/" <> _ = header(headers, "user-agent")
      assert {_, ""} = Integer.parse(header(headers, "webhook-timestamp"))

      assert Jason.decode!(body) == %{
               "id" => event.id,
               "type" => event.type,
               "timestamp" => DateTime.to_iso8601(event.occurred_at),
               "merchant_id" => event.merchant_id,
               "data" => event.payload
             }
    end

    test "Scenario: Two signatures during rotation" do
      %{endpoint: endpoint, secret: old_secret, delivery: delivery} = setup_delivery()
      {:ok, _endpoint, new_secret} = Courier.Endpoints.rotate_secret(endpoint)
      stub_response(200)

      assert :ok = run(delivery)

      assert_received {:request, "POST", _host, _path, headers, body}
      assert [new_sig, old_sig] = signatures(headers)
      assert valid_signature?(new_secret, new_sig, headers, body)
      assert valid_signature?(old_secret, old_sig, headers, body)
      refute valid_signature?(old_secret, new_sig, headers, body)
    end
  end

  describe "Requirement: Successful delivery" do
    test "Scenario: Endpoint answers 200" do
      %{delivery: delivery} = setup_delivery()
      stub_response(200)

      assert :ok = run(delivery)

      stored = reload(delivery)
      assert stored.status == "succeeded"
      assert %DateTime{} = stored.completed_at
      assert stored.next_attempt_at == nil
      assert stored.attempt_count == 1
      assert [%{number: 1, response_status: 200, error: nil}] = Audit.list_attempts(delivery.id)
    end
  end

  describe "Requirement: Non-retryable failures end the delivery" do
    test "Scenario: Client error" do
      %{delivery: delivery} = setup_delivery()
      stub_response(400, "bad request")

      assert :ok = run(delivery)

      stored = reload(delivery)
      assert stored.status == "failed"
      assert %DateTime{} = stored.completed_at
      assert [%{number: 1, response_status: 400}] = Audit.list_attempts(delivery.id)
    end

    test "Scenario: Redirect not followed" do
      %{delivery: delivery} = setup_delivery()
      test_pid = self()

      Req.Test.stub(Client, fn
        %{request_path: "/moved"} = conn ->
          send(test_pid, :location_called)
          Plug.Conn.send_resp(conn, 200, "moved")

        conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://hooks.public.test/moved")
          |> Plug.Conn.send_resp(302, "")
      end)

      assert :ok = run(delivery)

      refute_received :location_called
      assert reload(delivery).status == "failed"
      assert [%{number: 1, response_status: 302}] = Audit.list_attempts(delivery.id)
    end
  end

  describe "Requirement: Retry window ends retries" do
    test "Scenario: Window already ended" do
      {endpoint, _secret} = endpoint_fixture()
      event = event_fixture(%{merchant_id: endpoint.merchant_id})

      delivery =
        delivery_fixture(%{
          endpoint_id: endpoint.id,
          event_id: event.id,
          window_ends_at: DateTime.add(DateTime.utc_now(), -1, :second)
        })

      stub_response(200)

      assert :ok = run(delivery)

      refute_received {:request, _, _, _, _, _}
      stored = reload(delivery)
      assert stored.status == "failed"
      assert %DateTime{} = stored.completed_at
      assert stored.attempt_count == 0
      assert Audit.list_attempts(delivery.id) == []
    end
  end

  describe "Requirement: URL policy checked before every request" do
    test "Scenario: Host now resolves to a private address" do
      %{endpoint: endpoint, delivery: delivery} = setup_delivery()

      # The host now resolves (through Courier.Endpoints.TestResolver) to 10.0.0.5.
      private_url = "https://hooks.private.test/courier"
      {1, _} = Repo.update_all(where(Endpoint, id: ^endpoint.id), set: [url: private_url])

      assert Courier.Endpoints.TestResolver.resolve("hooks.private.test") ==
               {:ok, [{10, 0, 0, 5}]}

      stub_response(200)

      assert :ok = run(delivery)

      refute_received {:request, _, _, _, _, _}
      assert reload(delivery).status == "failed"
      assert [attempt] = Audit.list_attempts(delivery.id)
      assert attempt.response_status == nil
      assert attempt.url == private_url
      assert "url_rejected" <> _ = attempt.error
    end
  end

  describe "Requirement: Attempts are append-only" do
    test "Scenario: Attempt recorded" do
      %{endpoint: endpoint, delivery: delivery} = setup_delivery()
      body = String.duplicate("x", 10 * 1024)
      stub_response(500, body)

      assert {:snooze, seconds} = run(delivery)
      assert seconds >= 1

      assert [attempt] = Audit.list_attempts(delivery.id)
      assert attempt.number == 1
      assert attempt.response_status == 500
      assert attempt.response_body == binary_part(body, 0, 4096)
      assert is_integer(attempt.duration_ms) and attempt.duration_ms >= 0
      assert %DateTime{} = attempt.started_at
      assert attempt.url == endpoint.url
      assert attempt.request_headers["webhook-signature"] == "[redacted]"
      assert attempt.request_headers["courier-delivery-id"] == delivery.id
      assert attempt.request_headers["webhook-id"] == delivery.event_id

      stored = reload(delivery)
      assert stored.status == "pending"
      assert %DateTime{} = stored.next_attempt_at
    end
  end
end
