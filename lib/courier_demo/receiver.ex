defmodule CourierDemo.Receiver do
  @moduledoc """
  A demo webhook receiver: a plug, served by Bandit, that fails on purpose by
  path and verifies courier's Standard Webhooks signatures with its own code
  (never with `Courier.Delivery.Signer`, so it is an independent check).

    * `PUT /_secrets/:name` with `{"secret": "whsec_..."}` registers the
      secret used for `/hooks/:name/...` (in memory only).
    * `POST /hooks/:name/:behaviour` answers by behaviour: `ok` (`200`), `fail`
      (`500`), `rate-limit` (`429` with `Retry-After`), `bad-request` (`400`)
      and `timeout` (`200` after `:timeout_delay_ms`). With a secret registered
      for the name, a request with a wrong signature or a stale timestamp is
      answered `401`; without one the request is not checked.
    * Anything else answers `404`.

  ## Options

    * `:ip` - address to bind (default `{127, 0, 0, 1}`)
    * `:port` - port to bind (default `4001`)
    * `:timeout_delay_ms` - delay of the `timeout` behaviour (default `35_000`,
      longer than courier's request deadline)
    * `:retry_after` - seconds in the `Retry-After` header (default `30`)
    * `:tolerance_seconds` - accepted clock difference (default `300`)
    * `:secrets` - name of the secrets agent (default
      `CourierDemo.Receiver.Secrets`), so several receivers can run at once
  """

  use Plug.Router, copy_opts_to_assign: :receiver

  require Logger

  alias CourierDemo.Receiver.Secrets

  @behaviours ~w(ok fail rate-limit bad-request timeout)
  @max_body_bytes 1_000_000
  @name_format ~r/\A[a-z0-9-]{1,64}\z/

  plug :match
  plug :dispatch

  @doc """
  A supervisor with the secrets agent and the Bandit server (child id
  `:server`). See the module documentation for the options.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    config = init(opts)

    bandit = [
      plug: {__MODULE__, opts},
      ip: Keyword.get(opts, :ip, {127, 0, 0, 1}),
      port: Keyword.get(opts, :port, 4001),
      startup_log: false
    ]

    children = [
      {Secrets, name: config.secrets},
      Supervisor.child_spec({Bandit, bandit}, id: :server)
    ]

    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {Supervisor, :start_link, [children, [strategy: :one_for_all]]},
      type: :supervisor
    }
  end

  @impl Plug
  def init(opts) do
    %{
      timeout_delay_ms: Keyword.get(opts, :timeout_delay_ms, 35_000),
      retry_after: Keyword.get(opts, :retry_after, 30),
      tolerance_seconds: Keyword.get(opts, :tolerance_seconds, 300),
      secrets: Keyword.get(opts, :secrets, Secrets)
    }
  end

  put "/_secrets/:name" do
    with true <- valid_name?(name),
         {:ok, body, conn} <- read_body(conn, length: @max_body_bytes),
         {:ok, %{"secret" => secret}} <- Jason.decode(body),
         :ok <- Secrets.put(conn.assigns.receiver.secrets, name, secret) do
      send_resp(conn, 204, "")
    else
      false -> send_resp(conn, 404, "not found")
      _invalid -> send_resp(conn, 422, "invalid secret")
    end
  end

  post "/hooks/:name/:behaviour" when behaviour in @behaviours do
    if valid_name?(name) do
      hook(conn, name, behaviour, conn.assigns.receiver)
    else
      send_resp(conn, 404, "not found")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp valid_name?(name), do: Regex.match?(@name_format, name)

  # The raw body is read here, without Plug.Parsers: the signature covers the
  # exact bytes.
  defp hook(conn, name, behaviour, config) do
    case read_body(conn, length: @max_body_bytes) do
      {:ok, body, conn} ->
        result = verify(conn, body, Secrets.key(config.secrets, name), config)

        Logger.info(
          "demo-receiver name=#{name} behaviour=#{behaviour} signature=#{result} " <>
            "webhook-id=#{header(conn, "webhook-id") || "-"} " <>
            "courier-delivery-id=#{header(conn, "courier-delivery-id") || "-"}"
        )

        if result == :invalid do
          send_resp(conn, 401, "invalid signature")
        else
          behave(conn, behaviour, config)
        end

      _too_large_or_error ->
        send_resp(conn, 413, "body too large")
    end
  end

  defp behave(conn, "ok", _config), do: send_resp(conn, 200, "ok")
  defp behave(conn, "fail", _config), do: send_resp(conn, 500, "fail")
  defp behave(conn, "bad-request", _config), do: send_resp(conn, 400, "bad request")

  defp behave(conn, "rate-limit", config) do
    conn
    |> put_resp_header("retry-after", to_string(config.retry_after))
    |> send_resp(429, "rate limited")
  end

  defp behave(conn, "timeout", config) do
    Process.sleep(config.timeout_delay_ms)
    send_resp(conn, 200, "ok")
  end

  # Standard Webhooks check, written independently of courier's signer.
  defp verify(_conn, _body, nil, _config), do: :unchecked

  defp verify(conn, body, key, config) do
    with id when is_binary(id) <- header(conn, "webhook-id"),
         timestamp when is_binary(timestamp) <- header(conn, "webhook-timestamp"),
         signatures when is_binary(signatures) <- header(conn, "webhook-signature"),
         true <- fresh?(timestamp, config.tolerance_seconds),
         expected = Base.encode64(:crypto.mac(:hmac, :sha256, key, "#{id}.#{timestamp}.#{body}")),
         true <- any_match?(signatures, expected) do
      :valid
    else
      _missing_stale_or_wrong -> :invalid
    end
  end

  defp fresh?(timestamp, tolerance) do
    case Integer.parse(timestamp) do
      {seconds, ""} -> abs(System.system_time(:second) - seconds) <= tolerance
      _not_an_integer -> false
    end
  end

  # Every entry is compared (no early exit) and each comparison is constant time.
  defp any_match?(signatures, expected) do
    signatures
    |> String.split(" ", trim: true)
    |> Enum.reduce(false, fn
      "v1," <> signature, matched -> Plug.Crypto.secure_compare(signature, expected) or matched
      _other_version, matched -> matched
    end)
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end
end
