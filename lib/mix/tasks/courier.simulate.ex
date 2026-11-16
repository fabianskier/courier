defmodule Mix.Tasks.Courier.Simulate do
  @shortdoc "Sends demo events to courier's ingestion API"

  @moduledoc """
  Sends events to `POST <url>/api/v1/events` at a steady rate, with a share of
  exact repeats (`CourierDemo.Simulator`), and prints a summary.

      $ mix courier.simulate --merchant ID [--merchant ID...] [options]

  ## Options

    * `--merchant ID` - merchant to send events for (required, repeatable)
    * `--token TOKEN` - API key with the `ingest` scope (default: the
      `COURIER_INGEST_TOKEN` environment variable; required)
    * `--url URL` - courier's base URL (default `http://localhost:4000`)
    * `--count N` - number of requests (default `100`, at least 1)
    * `--rate N` - requests per second (default `5`, 1 to 1000)
    * `--repeat-share S` - share of requests that repeat an earlier one with
      the same idempotency key and body (default `0.1`, from 0 to 1)
    * `--types A,B` - event types (default
      `payment.succeeded,payment.failed,refund.succeeded`)

  The courier application is not started: the task talks to the API like any
  producer. Missing or invalid options print what is wrong and exit with
  status 1 without sending anything. The token is never printed.

  ## Example

      $ COURIER_INGEST_TOKEN=ck_... mix courier.simulate \\
          --merchant 0d0c6e0a-6f0e-4f0e-9d51-6f0c1a2b3c4d --count 50 --rate 10
  """

  use Mix.Task

  alias CourierDemo.Simulator

  @switches [
    merchant: :keep,
    token: :string,
    url: :string,
    count: :integer,
    rate: :integer,
    repeat_share: :float,
    types: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    config = %{
      merchants: Keyword.get_values(opts, :merchant),
      token: Keyword.get(opts, :token) || System.get_env("COURIER_INGEST_TOKEN"),
      url: Keyword.get(opts, :url, "http://localhost:4000"),
      count: Keyword.get(opts, :count, 100),
      rate: Keyword.get(opts, :rate, 5),
      repeat_share: Keyword.get(opts, :repeat_share, 0.1),
      types: opts |> Keyword.get(:types) |> parse_types()
    }

    case parse_errors(rest, invalid) ++ validation_errors(config) do
      [] ->
        simulate(config)

      errors ->
        Enum.each(errors, &Mix.shell().error(&1))

        Mix.shell().error(
          "Usage: mix courier.simulate --merchant ID [--merchant ID...] [options]"
        )

        exit({:shutdown, 1})
    end
  end

  defp simulate(config) do
    # Compiles and loads the configuration without starting the application.
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:req)

    tally =
      config
      |> Map.take([:merchants, :count, :repeat_share, :types])
      |> Map.to_list()
      |> Simulator.plan()
      |> Simulator.run(token: config.token, url: config.url, rate: config.rate)

    tally |> summary() |> Enum.each(&Mix.shell().info(&1))
  end

  defp parse_types(nil), do: Simulator.default_types()

  defp parse_types(types) do
    types
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Only option names are echoed, never values: a value could be the token.
  defp parse_errors(rest, invalid) do
    Enum.map(invalid, fn {name, _value} -> "Invalid or unknown option #{name}." end) ++
      if(rest == [], do: [], else: ["Unexpected arguments: only options are accepted."])
  end

  defp validation_errors(config) do
    [
      {config.merchants != [], "A merchant is required (--merchant ID)."},
      {config.token not in [nil, ""], "A token is required (--token or COURIER_INGEST_TOKEN)."},
      {config.count >= 1, "The count must be at least 1 (--count)."},
      {config.rate in 1..1000, "The rate must be between 1 and 1000 (--rate)."},
      {config.repeat_share >= 0 and config.repeat_share <= 1,
       "The repeat share must be between 0 and 1 (--repeat-share)."},
      {config.types != [], "At least one event type is required (--types)."}
    ]
    |> Enum.reject(fn {valid?, _message} -> valid? end)
    |> Enum.map(fn {_valid?, message} -> message end)
  end

  defp summary(tally) do
    total = tally.new + tally.repeats + tally.failed + Enum.sum(Map.values(tally.rejected))

    rejected =
      tally.rejected
      |> Enum.sort()
      |> Enum.map(fn {status, n} -> "  #{n} rejected with status #{status}" end)

    [
      "Sent #{total} #{plural(total, "request")} in " <>
        "#{:erlang.float_to_binary(tally.elapsed_ms / 1000, decimals: 1)} s:",
      "  #{tally.new} new (202)",
      "  #{tally.repeats} #{plural(tally.repeats, "repeat")} (200)"
    ] ++ rejected ++ ["  #{tally.failed} failed (no response)"]
  end

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"
end
