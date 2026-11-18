import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/courier start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :courier, CourierWeb.Endpoint, server: true
end

config :courier, CourierWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# The admin token is the password of /admin/dashboard (HTTP Basic, any user
# name). Without it the dashboard answers 404. When unset, the fixed tokens in
# config/dev.exs and config/test.exs apply; production has no default.
case System.get_env("COURIER_ADMIN_TOKEN") do
  token when token in [nil, ""] -> :ok
  token -> config :courier, :admin_token, token
end

# Retention period in whole days for Courier.Retention (default 30, minimum 2,
# longer than the 24 h retry window). An invalid value stops the boot.
config :courier,
       :retention_days,
       Courier.Retention.parse_days(System.get_env("COURIER_RETENTION_DAYS"))

if config_env() == :dev do
  # Database connection from the environment (set in mise.toml [env]).
  # Falls back to the values in config/dev.exs when unset.
  if database_url = System.get_env("DATABASE_URL") do
    config :courier, Courier.Repo, url: database_url
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :courier, Courier.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Key for secrets encrypted at rest (Courier.Vault, AES-256-GCM).
  # Losing it makes stored endpoint secrets unreadable.
  encryption_key =
    System.get_env("COURIER_ENCRYPTION_KEY") ||
      raise """
      environment variable COURIER_ENCRYPTION_KEY is missing.
      It must be the base64 encoding of 32 random bytes.
      You can generate one by calling: openssl rand -base64 32
      """

  encryption_key =
    case Base.decode64(encryption_key) do
      {:ok, <<_::binary-size(32)>> = key} ->
        key

      _ ->
        raise """
        environment variable COURIER_ENCRYPTION_KEY is invalid.
        It must be the base64 encoding of exactly 32 bytes.
        You can generate one by calling: openssl rand -base64 32
        """
    end

  config :courier, Courier.Vault, key: encryption_key

  # Endpoint URL policy (SSRF protection). Production keeps the strict
  # defaults of config/config.exs: https only and no allowlisted hosts. The
  # two variables below relax it and are meant for the local Docker demo only
  # (compose.yaml), where the demo receiver is a plain-http service on the
  # private network:
  #
  #   COURIER_ALLOW_HTTP=true                accepts http endpoint URLs
  #   COURIER_ALLOWED_HOSTS=host-a,host-b    hosts exempt from the public-address check
  allowed_hosts =
    "COURIER_ALLOWED_HOSTS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  config :courier, Courier.Endpoints.URLPolicy,
    require_https: System.get_env("COURIER_ALLOW_HTTP") not in ~w(true 1),
    allowed_hosts: allowed_hosts

  host = System.get_env("PHX_HOST") || "example.com"

  config :courier, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :courier, CourierWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :courier, CourierWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :courier, CourierWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
