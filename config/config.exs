# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :courier,
  ecto_repos: [Courier.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Oban (open-source engine). Delivery queues are started per endpoint at runtime
# (see docs/decisions.md); the only static queue is `maintenance`.
config :courier, Oban,
  engine: Oban.Engines.Basic,
  repo: Courier.Repo,
  queues: [maintenance: 1],
  plugins: [
    # Fail pending deliveries whose retry window ended (e.g. disabled endpoints).
    {Oban.Plugins.Cron, crontab: [{"*/5 * * * *", Courier.Delivery.WindowSweeper}]},
    # Prune old, finished events once a day at 03:30 UTC (Oban accepts each
    # plugin once, so retention has its own Cron plugin; see Courier.Retention.Cron).
    {Courier.Retention.Cron, crontab: [{"30 3 * * *", Courier.Retention.Worker}]},
    # Keep finished jobs for 7 days so their history can be inspected.
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Rescue jobs left "executing" after a crash or restart.
    Oban.Plugins.Lifeline
  ]

# Endpoint URL policy (SSRF protection). Production uses these defaults;
# dev and test override them.
config :courier, Courier.Endpoints.URLPolicy,
  require_https: true,
  allowed_hosts: [],
  resolver: Courier.Endpoints.DNSResolver

# Configure the endpoint
config :courier, CourierWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CourierWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Courier.PubSub,
  live_view: [signing_salt: "s+G2BHZY"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
