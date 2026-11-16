defmodule CourierDemo.Seeds do
  @moduledoc """
  The demo data set: a `demo` API key, three merchants and five endpoints that
  point at the demo receiver's behaviours (`CourierDemo.Receiver`), one each.

  `run/1` creates the data through the public context functions and registers
  each endpoint's signing secret with the receiver; `report/1` renders what
  `priv/repo/seeds.exs` prints. Secrets go only to the receiver: they are never
  returned, printed or logged.

  Extra `Req` options for the registrations come from `config :courier,
  CourierDemo.Seeds, req_options: [...]` (tests use it to route requests to
  `Req.Test`).
  """

  alias Courier.{Access, Endpoints, Merchants}

  @key_name "demo"
  @scopes ~w(ingest read write)
  @default_receiver_url "http://localhost:4001"
  @timeout_ms 2_000

  # {merchant, [{endpoint name, receiver behaviour, endpoint settings}]}
  @data [
    {"Sunrise Bakery", [{"sunrise-ok", "ok", %{event_types: ["payment.*"]}}]},
    {"Harbor Outfitters",
     [
       {"harbor-fail", "fail", %{retry_window_seconds: 300}},
       {"harbor-rate-limit", "rate-limit", %{}}
     ]},
    {"Pine Hardware",
     [
       {"pine-bad-request", "bad-request", %{}},
       {"pine-timeout", "timeout", %{max_concurrency: 2}}
     ]}
  ]

  @type summary :: %{
          token: String.t(),
          receiver_url: String.t(),
          merchants: [%{id: Ecto.UUID.t(), name: String.t()}],
          endpoints: [
            %{id: Ecto.UUID.t(), name: String.t(), url: String.t(), registered: boolean()}
          ]
        }

  @doc """
  Creates the demo data and registers the endpoints' secrets with the receiver.

  The `demo` key is created first: when a key with that name already exists
  the database counts as seeded and nothing else is created. A receiver that
  cannot be reached or rejects a secret does not stop the seeding; the
  endpoint is reported with `registered: false`.

  ## Options

    * `:receiver_url` - the receiver's base URL (default: the value of
      `COURIER_DEMO_RECEIVER_URL`, else `#{@default_receiver_url}`)
  """
  @spec run(keyword()) :: {:ok, summary()} | {:error, :already_seeded}
  def run(opts \\ []) do
    receiver_url = opts |> receiver_url() |> String.trim_trailing("/")

    case Access.create_key(%{name: @key_name, scopes: @scopes}) do
      {:ok, %{token: token}} ->
        merchants = Enum.map(@data, &create_merchant(&1, receiver_url))

        {:ok,
         %{
           token: token,
           receiver_url: receiver_url,
           merchants: Enum.map(merchants, &Map.take(&1, [:id, :name])),
           endpoints: Enum.flat_map(merchants, & &1.endpoints)
         }}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :name) do
          {:error, :already_seeded}
        else
          raise "could not create the demo key: #{inspect(changeset.errors)}"
        end
    end
  end

  defp receiver_url(opts) do
    Keyword.get_lazy(opts, :receiver_url, fn ->
      System.get_env("COURIER_DEMO_RECEIVER_URL", @default_receiver_url)
    end)
  end

  defp create_merchant({name, endpoints}, receiver_url) do
    {:ok, merchant} = Merchants.create_merchant(%{name: name})

    %{
      id: merchant.id,
      name: merchant.name,
      endpoints: Enum.map(endpoints, &create_endpoint(&1, merchant, receiver_url))
    }
  end

  defp create_endpoint({name, behaviour, settings}, merchant, receiver_url) do
    attrs =
      Map.merge(settings, %{
        merchant_id: merchant.id,
        url: "#{receiver_url}/hooks/#{name}/#{behaviour}",
        description: name
      })

    case Endpoints.create_endpoint(attrs) do
      {:ok, endpoint, secret} ->
        %{
          id: endpoint.id,
          name: name,
          url: endpoint.url,
          registered: register_secret(receiver_url, name, secret)
        }

      {:error, changeset} ->
        raise "could not create the demo endpoint #{name}: #{inspect(changeset.errors)}"
    end
  end

  # The failure reason is dropped on purpose: nothing about the request, which
  # carries the secret, is returned or logged.
  defp register_secret(receiver_url, name, secret) do
    options =
      Keyword.merge(
        [
          url: "#{receiver_url}/_secrets/#{name}",
          json: %{secret: secret},
          retry: false,
          receive_timeout: @timeout_ms,
          connect_options: [timeout: @timeout_ms]
        ],
        config_req_options()
      )

    match?({:ok, %Req.Response{status: 204}}, Req.put(options))
  end

  defp config_req_options do
    :courier
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_options, [])
  end

  @doc """
  Renders the result of `run/1` as the text the seeds script prints: the
  token (shown only here), the merchants, the endpoints, a warning for the
  endpoints whose secret the receiver did not take, and a `mix courier.simulate`
  command that can be run as printed. It never contains a signing secret.
  """
  @spec report({:ok, summary()} | {:error, :already_seeded}) :: String.t()
  def report({:error, :already_seeded}) do
    """
    The database is already seeded (an API key named "#{@key_name}" exists): nothing was created.
    To start again from an empty database, run: mix ecto.reset
    """
  end

  def report({:ok, summary}) do
    merchant_options = Enum.map_join(summary.merchants, " ", &"--merchant #{&1.id}")

    """
    Demo data created.

    API key "#{@key_name}" (#{Enum.join(@scopes, ", ")}), shown only once:
      #{summary.token}

    Merchants:
    #{lines(summary.merchants, &"#{&1.id}  #{&1.name}")}

    Endpoints:
    #{lines(summary.endpoints, &"#{&1.id}  #{&1.url}")}
    #{registration_note(summary)}
    Send events with:
      mix courier.simulate --token #{summary.token} #{merchant_options}
    """
  end

  defp registration_note(summary) do
    case Enum.reject(summary.endpoints, & &1.registered) do
      [] ->
        "\nEvery endpoint's signing secret is registered with the receiver at #{summary.receiver_url}.\n"

      unregistered ->
        """

        WARNING: the receiver at #{summary.receiver_url} did not take the signing secret of:
        #{lines(unregistered, & &1.name)}
        Requests to these endpoints will be answered unchecked (signatures are not verified).
        Start the receiver (mix courier.demo.receiver) and run mix ecto.reset to seed again.
        """
    end
  end

  defp lines(items, format), do: Enum.map_join(items, "\n", &("  " <> format.(&1)))
end
