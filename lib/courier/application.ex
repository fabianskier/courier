defmodule Courier.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Courier.Vault,
      Courier.Repo,
      # After the repo: its poller measures queue lag through Courier.Repo
      # as soon as it starts, and stops before the repo on shutdown.
      CourierWeb.Telemetry,
      # Webhook delivery: Finch keeps one pool per origin, each at least as
      # large as the largest allowed endpoint max_concurrency (50). The
      # connect timeout lives here because Req does not accept
      # :connect_options together with a named Finch pool.
      {Finch,
       name: Courier.Finch,
       pools: %{default: [size: 50, conn_opts: [transport_opts: [timeout: 5_000]]]}},
      # Runs each webhook request so it can be killed at its total deadline.
      {Task.Supervisor, name: Courier.Delivery.TaskSupervisor},
      {Oban, Application.fetch_env!(:courier, Oban)},
      # Starts one queue per enabled endpoint; must come after Oban.
      Courier.Delivery.QueueManager,
      {DNSCluster, query: Application.get_env(:courier, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Courier.PubSub},
      # MCP sessions, served through the endpoint at /mcp. Always started:
      # by default the library starts only when an HTTP server is being
      # served, but the route exists whenever the endpoint does.
      {CourierMCP.Server, transport: {:streamable_http, start: true}},
      # Start a worker by calling: Courier.Worker.start_link(arg)
      # {Courier.Worker, arg},
      # Start to serve requests, typically the last entry
      CourierWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Courier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CourierWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
