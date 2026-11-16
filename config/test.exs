import Config

# Jobs are only inserted in tests; run them explicitly with Oban.Testing.
config :courier, Oban, testing: :manual

# Fixed, NON-SECRET encryption key for tests only (exactly 32 bytes).
# Production reads COURIER_ENCRYPTION_KEY in config/runtime.exs.
config :courier, Courier.Vault, key: "courier-test-key-not-a-secret!!!"

# Fixed, NON-SECRET admin token for tests only.
config :courier, :admin_token, "courier-test-admin-token-not-a-secret"

# URL policy in tests never touches the network: hosts resolve by convention
# (see test/support/test_resolver.ex).
config :courier, Courier.Endpoints.URLPolicy,
  require_https: true,
  allowed_hosts: [],
  resolver: Courier.Endpoints.TestResolver

# Webhook requests go to Req.Test stubs, never to the network.
config :courier, Courier.Delivery.Client, plug: {Req.Test, Courier.Delivery.Client}

# Oban runs no queues with testing: :manual; the queue manager talks to a stub
# that does nothing unless a test registers itself (test/support/test_queue_control.ex).
config :courier, :queue_control, Courier.Delivery.TestQueueControl

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :courier, Courier.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "courier_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :courier, CourierWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "FoBDw4wsDm+oKArdG7mW2AK590cJvXAjujTMWLiAaFkxTPDB3pxzG+w96mn8wzPk",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
