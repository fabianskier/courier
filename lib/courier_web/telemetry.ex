defmodule CourierWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("courier.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("courier.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("courier.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("courier.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("courier.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Courier Metrics
      counter("courier.event.ingested.count",
        tags: [:type],
        description: "Events ingested, by type"
      ),
      sum("courier.event.ingested.deliveries",
        description: "Deliveries created by ingested events"
      ),
      summary("courier.attempt.stop.duration",
        unit: {:native, :millisecond},
        tags: [:outcome, :status_class],
        description: "How long attempts take, by outcome and status class"
      ),
      counter("courier.attempt.stop.duration",
        tags: [:outcome],
        description: "Attempts, by outcome"
      ),
      summary("courier.attempt.stop.since_created_ms",
        unit: :millisecond,
        tags: [:number],
        keep: &(&1.number == 1),
        description: "Time from a delivery's creation to its first attempt"
      ),
      counter("courier.attempt.exception.duration",
        description: "Attempts whose request raised"
      ),
      counter("courier.delivery.succeeded.attempts",
        description: "Deliveries that succeeded"
      ),
      summary("courier.delivery.succeeded.total_ms",
        unit: :millisecond,
        description: "Time from a delivery's creation to its success"
      ),
      counter("courier.delivery.failed.attempts",
        tags: [:reason],
        description: "Deliveries that failed for good, by reason"
      ),
      counter("courier.delivery.retry_scheduled.delay_seconds",
        description: "Retries scheduled"
      ),
      summary("courier.delivery.retry_scheduled.delay_seconds",
        unit: :second,
        description: "Delay until the next attempt"
      ),
      counter("courier.endpoint.degraded.consecutive_failures",
        description: "Endpoints marked degraded"
      ),
      counter("courier.endpoint.recovered.count",
        description: "Endpoints that recovered"
      ),
      last_value("courier.queue.lag.seconds",
        unit: :second,
        tags: [:queue],
        description: "How long the oldest available job of an endpoint queue has waited"
      ),
      last_value("courier.queue.lag.available",
        tags: [:queue],
        description: "Available jobs in an endpoint queue"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {Courier.Delivery.QueueLag, :measure, []}
    ]
  end
end
