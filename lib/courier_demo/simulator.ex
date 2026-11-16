defmodule CourierDemo.Simulator do
  @moduledoc """
  A demo producer: sends events to courier's ingestion API
  (`POST /api/v1/events`) at a steady rate, with a share of exact repeats.

  The work is split in two: `plan/2` builds the whole list of requests first,
  so repeats are byte-identical copies of earlier requests, and `run/2` sends
  them on a schedule and tallies the answers. It talks to the API like any
  producer and needs neither the courier application nor a database.

  Extra `Req` options come from `config :courier, CourierDemo.Simulator,
  req_options: [...]` (tests use it to route requests to `Req.Test`).
  """

  @default_types ~w(payment.succeeded payment.failed refund.succeeded)
  @currencies ~w(USD EUR GBP)
  @max_concurrency 20

  @typedoc "One planned request: its idempotency key and its encoded JSON body."
  @type request :: {idempotency_key :: String.t(), body :: String.t()}

  @typedoc "Returns a float in `[0.0, 1.0)`, like `:rand.uniform/0`."
  @type rand :: (-> float())

  @type tally :: %{
          new: non_neg_integer(),
          repeats: non_neg_integer(),
          rejected: %{optional(pos_integer()) => pos_integer()},
          failed: non_neg_integer(),
          elapsed_ms: non_neg_integer()
        }

  @doc "The event types used when none are given."
  @spec default_types() :: [String.t()]
  def default_types, do: @default_types

  @doc """
  Builds the requests of a run, in sending order.

  Request `i` is a repeat with probability `:repeat_share` (never the first
  one): a copy, key and body, of a random earlier new request. Otherwise it
  is a new event with the key `sim-<run id>-<i>`, a random type and merchant
  and a made-up payload, encoded once.

  ## Options

    * `:merchants` - merchant ids to pick from (required, not empty)
    * `:count` - number of requests (default `100`)
    * `:repeat_share` - share of repeats, from `0` to `1` (default `0.1`)
    * `:types` - event types to pick from (default `default_types/0`)
    * `:run_id` - prefix that makes the keys unique (default: random)

  `rand` supplies every random choice, so a test can make the plan
  deterministic.
  """
  @spec plan(keyword(), rand()) :: [request()]
  def plan(opts, rand \\ &:rand.uniform/0) do
    merchants = Keyword.fetch!(opts, :merchants)
    count = Keyword.get(opts, :count, 100)
    repeat_share = Keyword.get(opts, :repeat_share, 0.1)
    types = Keyword.get(opts, :types, @default_types)
    run_id = Keyword.get_lazy(opts, :run_id, &random_run_id/0)

    {requests, _news} =
      Enum.reduce(0..(count - 1)//1, {[], %{}}, fn i, {requests, news} ->
        if map_size(news) > 0 and rand.() < repeat_share do
          {[Map.fetch!(news, index(rand, map_size(news))) | requests], news}
        else
          request = new_request(run_id, i, types, merchants, rand)
          {[request | requests], Map.put(news, map_size(news), request)}
        end
      end)

    Enum.reverse(requests)
  end

  defp new_request(run_id, i, types, merchants, rand) do
    body =
      Jason.encode!(%{
        "type" => pick(types, rand),
        "merchant_id" => pick(merchants, rand),
        "payload" => %{
          "amount" => 100 + index(rand, 99_900),
          "currency" => pick(@currencies, rand),
          "reference" => "order-#{run_id}-#{i}"
        }
      })

    {"sim-#{run_id}-#{i}", body}
  end

  defp pick(list, rand), do: Enum.at(list, index(rand, length(list)))

  # An index in 0..(size - 1), also when `rand` returns exactly 1.0.
  defp index(rand, size), do: min(trunc(rand.() * size), size - 1)

  defp random_run_id, do: Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

  @doc """
  Sends the planned requests and returns the tally.

  Request `i` is sent no earlier than `i * 1000 / rate` ms after the start,
  with up to #{@max_concurrency} requests in flight, so a slow API lowers the
  effective rate instead of piling requests up. Requests are never retried.

  ## Options

    * `:token` - API key with the `ingest` scope (required)
    * `:url` - courier's base URL (default `http://localhost:4000`)
    * `:rate` - requests per second (default `5`)

  The tally counts `202` answers as `:new`, `200` as `:repeats`, any other
  status under `:rejected` (by status) and requests without a response as
  `:failed`; `:elapsed_ms` is the duration of the run.
  """
  @spec run([request()], keyword()) :: tally()
  def run(plan, opts) do
    interval_ms = 1000 / Keyword.get(opts, :rate, 5)
    req = build_req(opts)
    start = System.monotonic_time(:millisecond)

    tally =
      plan
      |> Stream.with_index()
      |> Task.async_stream(
        fn {request, i} ->
          wait_until(start + round(i * interval_ms))
          send_request(req, request)
        end,
        max_concurrency: @max_concurrency,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.reduce(%{new: 0, repeats: 0, rejected: %{}, failed: 0}, fn {:ok, result}, tally ->
        count(tally, result)
      end)

    Map.put(tally, :elapsed_ms, System.monotonic_time(:millisecond) - start)
  end

  defp build_req(opts) do
    base_url = Keyword.get(opts, :url, "http://localhost:4000")

    [
      url: String.trim_trailing(base_url, "/") <> "/api/v1/events",
      auth: {:bearer, Keyword.fetch!(opts, :token)},
      headers: [{"content-type", "application/json"}],
      retry: false
    ]
    |> Keyword.merge(config_req_options())
    |> Req.new()
  end

  defp config_req_options do
    :courier
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_options, [])
  end

  defp wait_until(due) do
    case due - System.monotonic_time(:millisecond) do
      ms when ms > 0 -> Process.sleep(ms)
      _due_or_late -> :ok
    end
  end

  defp send_request(req, {key, body}) do
    case Req.post(req, headers: [{"idempotency-key", key}], body: body) do
      {:ok, %Req.Response{status: status}} -> status
      {:error, _exception} -> :failed
    end
  end

  defp count(tally, 202), do: Map.update!(tally, :new, &(&1 + 1))
  defp count(tally, 200), do: Map.update!(tally, :repeats, &(&1 + 1))
  defp count(tally, :failed), do: Map.update!(tally, :failed, &(&1 + 1))

  defp count(tally, status) do
    Map.update!(tally, :rejected, &Map.update(&1, status, 1, fn n -> n + 1 end))
  end
end
