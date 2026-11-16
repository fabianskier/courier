defmodule CourierDemo.CLI do
  @moduledoc """
  What the demo's command-line entry points share: the simulator's option
  parsing, validation and summary, used by `mix courier.simulate` and by the
  release's `bin/simulate`.

  `simulate/1` is the release entry point. It needs no Mix and no running
  courier application, and returns the exit status instead of halting.
  """

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

  @type config :: %{
          merchants: [String.t()],
          token: String.t(),
          url: String.t(),
          count: integer(),
          rate: integer(),
          repeat_share: number(),
          types: [String.t()]
        }

  @doc """
  Parses and validates the simulator's options.

  Returns `{:ok, config}` or `{:error, messages}` with one message per
  problem. The token defaults to `COURIER_INGEST_TOKEN` in `env`. Messages
  name options, never their values: a value could be the token.
  """
  @spec parse_simulate([String.t()], %{optional(String.t()) => String.t()}) ::
          {:ok, config()} | {:error, [String.t()]}
  def parse_simulate(args, env \\ System.get_env()) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    config = %{
      merchants: Keyword.get_values(opts, :merchant),
      token: Keyword.get(opts, :token) || env["COURIER_INGEST_TOKEN"],
      url: Keyword.get(opts, :url, "http://localhost:4000"),
      count: Keyword.get(opts, :count, 100),
      rate: Keyword.get(opts, :rate, 5),
      repeat_share: Keyword.get(opts, :repeat_share, 0.1),
      types: opts |> Keyword.get(:types) |> parse_types()
    }

    case parse_errors(rest, invalid) ++ validation_errors(config) do
      [] -> {:ok, config}
      errors -> {:error, errors}
    end
  end

  @doc "Plans and sends the run described by a valid `config`, and returns the tally."
  @spec run_simulation(config()) :: Simulator.tally()
  def run_simulation(config) do
    config
    |> Map.take([:merchants, :count, :repeat_share, :types])
    |> Map.to_list()
    |> Simulator.plan()
    |> Simulator.run(token: config.token, url: config.url, rate: config.rate)
  end

  @doc "The lines of the run summary: counts only, never the token."
  @spec summary(Simulator.tally()) :: [String.t()]
  def summary(tally) do
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

  @doc """
  The release entry point of the simulator (`bin/simulate`).

  Prints the summary to standard output and returns `0`; with missing or
  invalid options prints what is wrong and a usage line to standard error,
  sends nothing and returns `1`.
  """
  @spec simulate([String.t()]) :: 0 | 1
  def simulate(args) do
    case parse_simulate(args) do
      {:ok, config} ->
        {:ok, _apps} = Application.ensure_all_started(:req)
        config |> run_simulation() |> summary() |> Enum.each(&IO.puts/1)
        0

      {:error, messages} ->
        Enum.each(messages, &IO.puts(:stderr, &1))
        IO.puts(:stderr, "Usage: bin/simulate --merchant ID [--merchant ID...] [options]")
        1
    end
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

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"
end
