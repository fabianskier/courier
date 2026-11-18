defmodule CourierDemo.Load do
  @moduledoc """
  The load test: sends distinct events at a rate with `CourierDemo.Simulator`,
  then measures the run from the database and reports

    * ingestion: requests sent, achieved rate, statuses, failures and the
      client latency p50, p95 and p99;
    * delivery: for the run's deliveries (those of the given merchants'
      events created between the first and the last request, except
      `skipped` ones and resends), the time to first attempt p50 and p95
      overall and per endpoint, the attempts per second since the start, and
      how many deliveries had no attempt yet.

  Both timestamps of the time to first attempt (`deliveries.inserted_at` and
  `attempts.started_at`) are written by courier, so the measure includes the
  queueing, not only HTTP. It reads through `Courier.Repo`, which the caller
  starts (`CourierDemo.CLI.run_load/1`).
  """

  import Ecto.Query

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Repo
  alias CourierDemo.Load.Stats
  alias CourierDemo.Simulator

  @switches [
    merchant: :keep,
    token: :string,
    url: :string,
    count: :integer,
    rate: :integer,
    wait: :integer
  ]

  @type config :: %{
          merchants: [String.t()],
          token: String.t(),
          url: String.t(),
          count: integer(),
          rate: integer(),
          wait: integer()
        }

  @typedoc "The run's deliveries: the merchants and the creation interval."
  @type window :: %{merchants: [String.t()], from: DateTime.t(), to: DateTime.t()}

  @typedoc "One delivery of the run: endpoint URL, creation, first attempt start (or `nil`)."
  @type row :: {String.t(), DateTime.t(), DateTime.t() | nil}

  @doc """
  Parses and validates the load options.

  Returns `{:ok, config}` or `{:error, messages}` with one message per
  problem. The token defaults to `COURIER_INGEST_TOKEN` in `env`. Messages
  name options, never their values: a value could be the token.
  """
  @spec parse([String.t()], %{optional(String.t()) => String.t()}) ::
          {:ok, config()} | {:error, [String.t()]}
  def parse(args, env \\ System.get_env()) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    config = %{
      merchants: Keyword.get_values(opts, :merchant),
      token: Keyword.get(opts, :token) || env["COURIER_INGEST_TOKEN"],
      url: Keyword.get(opts, :url, "http://localhost:4000"),
      count: Keyword.get(opts, :count, 500),
      rate: Keyword.get(opts, :rate, 50),
      wait: Keyword.get(opts, :wait, 30)
    }

    case parse_errors(rest, invalid) ++ validation_errors(config) do
      [] -> {:ok, config}
      errors -> {:error, errors}
    end
  end

  defp parse_errors(rest, invalid) do
    Enum.map(invalid, fn {name, _value} -> "Invalid or unknown option #{name}." end) ++
      if(rest == [], do: [], else: ["Unexpected arguments: only options are accepted."])
  end

  defp validation_errors(config) do
    [
      {config.merchants != [], "A merchant is required (--merchant ID)."},
      {Enum.all?(config.merchants, &match?({:ok, _}, Ecto.UUID.cast(&1))),
       "Every merchant must be a UUID (--merchant)."},
      {config.token not in [nil, ""], "A token is required (--token or COURIER_INGEST_TOKEN)."},
      {config.rate >= 1, "The rate must be a positive integer (--rate)."},
      {config.count >= 1, "The count must be a positive integer (--count)."},
      {config.wait >= 1, "The wait must be a positive integer (--wait)."}
    ]
    |> Enum.reject(fn {valid?, _message} -> valid? end)
    |> Enum.map(fn {_valid?, message} -> message end)
  end

  @doc """
  Runs the load test described by a valid `config` and returns the report lines.

  `sleep` waits the given milliseconds between the checks for first attempts
  (tests replace it).
  """
  @spec run(config(), (non_neg_integer() -> any())) :: [String.t()]
  def run(config, sleep \\ &Process.sleep/1) do
    started_at = DateTime.utc_now()
    tally = send_events(config)
    window = %{merchants: config.merchants, from: started_at, to: DateTime.utc_now()}

    waited_s = wait_for_first_attempts(window, config.wait, sleep)
    now = DateTime.utc_now()

    attempts_per_second =
      Stats.rate(count_attempts(started_at, now), DateTime.diff(now, started_at, :millisecond))

    ingestion_report(tally) ++
      delivery_report(delivery_rows(window), %{
        waited_s: waited_s,
        attempts_per_second: attempts_per_second
      })
  end

  @doc "Sends `count` new events (no repeats) at `rate`, timing every request."
  @spec send_events(config()) :: Simulator.tally()
  def send_events(config) do
    [merchants: config.merchants, count: config.count, repeat_share: 0.0]
    |> Simulator.plan()
    |> Simulator.run(token: config.token, url: config.url, rate: config.rate, latencies: true)
  end

  @doc """
  Waits, checking every second, until every delivery of `window` has an
  attempt number 1 or `wait_s` seconds have passed. Returns the seconds waited.
  """
  @spec wait_for_first_attempts(window(), non_neg_integer(), (non_neg_integer() -> any())) ::
          non_neg_integer()
  def wait_for_first_attempts(window, wait_s, sleep \\ &Process.sleep/1) do
    Enum.reduce_while(0..wait_s//1, 0, fn waited_s, _acc ->
      if waited_s == wait_s or count_without_attempt(window) == 0 do
        {:halt, waited_s}
      else
        sleep.(1000)
        {:cont, waited_s + 1}
      end
    end)
  end

  @doc "The number of deliveries of `window` without an attempt number 1."
  @spec count_without_attempt(window()) :: non_neg_integer()
  def count_without_attempt(window) do
    window
    |> run_deliveries()
    |> join(:left, [d], a in Attempt, on: a.delivery_id == d.id and a.number == 1)
    |> where([d, _e, a], is_nil(a.id))
    |> select([d], count(d.id))
    |> Repo.one()
  end

  @doc "Every delivery of `window` with its endpoint URL and its first attempt start."
  @spec delivery_rows(window()) :: [row()]
  def delivery_rows(window) do
    window
    |> run_deliveries()
    |> join(:inner, [d], ep in assoc(d, :endpoint))
    |> join(:left, [d], a in Attempt, on: a.delivery_id == d.id and a.number == 1)
    |> select([d, _e, ep, a], {ep.url, d.inserted_at, a.started_at})
    |> Repo.all()
  end

  defp run_deliveries(window) do
    from d in Delivery,
      join: e in assoc(d, :event),
      where:
        e.merchant_id in ^window.merchants and d.inserted_at >= ^window.from and
          d.inserted_at <= ^window.to and d.status != "skipped" and is_nil(d.resend_of_id)
  end

  @doc "The number of attempts, of any delivery, that started between `from` and `to`."
  @spec count_attempts(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def count_attempts(from, to) do
    Attempt
    |> where([a], a.started_at >= ^from and a.started_at <= ^to)
    |> select([a], count(a.id))
    |> Repo.one()
  end

  @doc "The ingestion lines of the report for a tally with `:latencies_ms`."
  @spec ingestion_report(Simulator.tally()) :: [String.t()]
  def ingestion_report(tally) do
    statuses =
      tally.rejected
      |> Map.put(202, tally.new)
      |> Map.put(200, tally.repeats)
      |> Enum.reject(fn {_status, n} -> n == 0 end)
      |> Enum.sort()

    sent = tally.failed + Enum.sum(Enum.map(statuses, &elem(&1, 1)))
    latencies = Map.get(tally, :latencies_ms, [])

    counts =
      Enum.map(statuses, fn {status, n} -> "#{n} x #{status}" end) ++
        ["#{tally.failed} failed"]

    [
      "Ingestion: #{sent} sent in " <>
        "#{:erlang.float_to_binary(tally.elapsed_ms / 1000, decimals: 1)} s " <>
        "(#{Stats.format_rate(Stats.rate(sent, tally.elapsed_ms))}): " <>
        Enum.join(counts, ", "),
      "  latency " <> percentiles(latencies, [50, 95, 99])
    ]
  end

  @doc """
  The delivery lines of the report for the run's `rows`, the seconds waited
  for first attempts and the attempts per second.
  """
  @spec delivery_report([row()], %{
          waited_s: non_neg_integer(),
          attempts_per_second: number() | nil
        }) ::
          [String.t()]
  def delivery_report(rows, %{waited_s: waited_s, attempts_per_second: attempts_per_second}) do
    without = Enum.count(rows, fn {_url, _inserted_at, started_at} -> is_nil(started_at) end)

    endpoints =
      rows
      |> Enum.group_by(fn {url, _inserted_at, _started_at} -> url end)
      |> Enum.sort()
      |> Enum.map(fn {url, endpoint_rows} -> endpoint_line(url, endpoint_rows) end)

    [
      "Delivery: #{length(rows)} #{plural(length(rows), "delivery", "deliveries")}, " <>
        "#{without} without an attempt yet after #{waited_s} s",
      "  time to first attempt " <> percentiles(times_to_first_attempt(rows), [50, 95]),
      "  attempts #{Stats.format_rate(attempts_per_second)}"
    ] ++ endpoints
  end

  defp endpoint_line(url, rows) do
    times = times_to_first_attempt(rows)

    "  #{url}  #{length(rows)} #{plural(length(rows), "delivery", "deliveries")}, " <>
      "#{length(times)} #{plural(length(times), "attempt", "attempts")}  " <>
      percentiles(times, [50, 95])
  end

  defp times_to_first_attempt(rows) do
    for {_url, inserted_at, %DateTime{} = started_at} <- rows,
        do: DateTime.diff(started_at, inserted_at, :microsecond) / 1000
  end

  defp percentiles(values, ps) do
    Enum.map_join(ps, ", ", fn p -> "p#{p} #{Stats.format_ms(Stats.percentile(values, p))}" end)
  end

  defp plural(1, singular, _plural), do: singular
  defp plural(_n, _singular, plural), do: plural
end
