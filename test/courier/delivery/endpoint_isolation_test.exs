defmodule Courier.Delivery.EndpointIsolationTest do
  # Real Oban queues, real HTTP servers and application config overrides:
  # the sandbox runs in shared mode and nothing else may run meanwhile.
  use Courier.DataCase, async: false

  import Courier.AuditFixtures
  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Delivery.Client
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.IsolationReceiver
  alias Courier.Delivery.Queues
  alias Courier.Delivery.Worker
  alias Courier.Endpoints.URLPolicy

  @oban Courier.IsolationOban
  @slow_delay_ms 3_000
  @max_concurrency 2
  @slow_jobs 6
  @deadline_ms 2_000

  setup do
    # Loopback over plain http is allowed, and requests go through Finch to
    # the real servers instead of Req.Test stubs.
    override_env(URLPolicy,
      require_https: false,
      allowed_hosts: ["127.0.0.1"],
      resolver: Courier.Endpoints.TestResolver
    )

    override_env(Client, [])

    slow_port = start_receiver(:slow, @slow_delay_ms)
    fast_port = start_receiver(:fast, 0)

    start_supervised!({
      Oban,
      # Jobs still waiting for the slow endpoint are dropped at the end.
      name: @oban,
      repo: Courier.Repo,
      engine: Oban.Engines.Basic,
      testing: :disabled,
      notifier: Oban.Notifiers.Isolated,
      peer: Oban.Peers.Isolated,
      stager: [interval: 25],
      plugins: [],
      queues: [],
      shutdown_grace_period: 0
    })

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :job, :stop],
        &IsolationReceiver.handle_job_stop/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    %{slow_port: slow_port, fast_port: fast_port}
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

  # Starts a receiver on a free loopback port and returns the port.
  defp start_receiver(name, delay_ms) do
    # The short shutdown timeout stops the server without waiting for
    # requests that are still sleeping when the test ends.
    opts = [
      plug: {IsolationReceiver, name: name, notify: self(), delay_ms: delay_ms},
      ip: :loopback,
      port: 0,
      startup_log: false,
      thousand_island_options: [shutdown_timeout: 100]
    ]

    pid = start_supervised!(Supervisor.child_spec({Bandit, opts}, id: {:receiver, name}))
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    port
  end

  defp endpoint_with_queue(port) do
    {endpoint, _secret} =
      endpoint_fixture(%{url: "http://127.0.0.1:#{port}/hook", max_concurrency: @max_concurrency})

    :ok =
      Oban.start_queue(@oban,
        queue: Queues.name(endpoint.id),
        limit: endpoint.max_concurrency,
        local_only: true
      )

    endpoint
  end

  # Creates a pending delivery and its job in the endpoint's queue.
  defp enqueue_delivery(endpoint) do
    event = event_fixture(%{merchant_id: endpoint.merchant_id})
    delivery = delivery_fixture(%{endpoint_id: endpoint.id, event_id: event.id})

    {:ok, _job} =
      Oban.insert(
        @oban,
        Worker.new(%{delivery_id: delivery.id}, queue: Queues.name(endpoint.id))
      )

    delivery
  end

  defp count_jobs(endpoint, state) do
    queue = Queues.name(endpoint.id)
    Repo.aggregate(from(j in Oban.Job, where: j.queue == ^queue and j.state == ^state), :count)
  end

  describe "Requirement: Endpoints are isolated from each other" do
    test "Scenario: Slow endpoint does not delay another", ports do
      slow = endpoint_with_queue(ports.slow_port)
      fast = endpoint_with_queue(ports.fast_port)

      # More jobs than the slow endpoint's concurrency limit.
      for _ <- 1..@slow_jobs, do: enqueue_delivery(slow)

      # The slow endpoint is saturated: every slot is waiting for an answer.
      for _ <- 1..@max_concurrency, do: assert_receive({:receiver_request, :slow}, @deadline_ms)

      created = System.monotonic_time(:millisecond)
      %DeliveryRecord{id: fast_id} = enqueue_delivery(fast)

      assert_receive {:job_stop, ^fast_id, :success}, @deadline_ms
      elapsed_ms = System.monotonic_time(:millisecond) - created

      assert %DeliveryRecord{status: "succeeded", attempt_count: 1} =
               Repo.get!(DeliveryRecord, fast_id)

      assert elapsed_ms < @deadline_ms
      assert_received {:receiver_request, :fast}

      # Meanwhile the slow endpoint is still busy: its limit of jobs is
      # running, the rest wait in its own queue, and none has finished.
      assert count_jobs(slow, "executing") == @max_concurrency
      assert count_jobs(slow, "available") == @slow_jobs - @max_concurrency
      refute_received {:receiver_request, :slow}
      refute_received {:job_stop, _delivery_id, _state}

      assert Repo.aggregate(
               from(d in DeliveryRecord,
                 where: d.endpoint_id == ^slow.id and d.status == "pending"
               ),
               :count
             ) == @slow_jobs
    end
  end
end
