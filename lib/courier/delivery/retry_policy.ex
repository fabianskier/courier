defmodule Courier.Delivery.RetryPolicy do
  @moduledoc """
  Pure functions that decide what happens after a delivery attempt.

  - `classify/2` turns a client result into `:success`, `:retry` or `:give_up`.
  - `delay/3` computes the wait before the next attempt: capped exponential
    backoff with full jitter, honouring a `Retry-After` value up to the cap.
  - `parse_retry_after/2` reads a `Retry-After` header (delta seconds or an
    HTTP date).
  - `next/3` schedules the next attempt, or reports that the retry window
    has ended.
  """

  @base 10
  @cap 3600

  @type result ::
          {:ok, %{required(:status) => integer(), optional(atom()) => term()}} | {:error, term()}
  @type outcome :: :success | :retry | :give_up

  @doc """
  Classifies the result of an attempt.

  `2xx` succeeds; network errors, `408`, `429` and `5xx` are retried; `3xx`
  gives up; any other `4xx` is retried only when `retry_on_4xx` is true.
  """
  @spec classify(result() | integer(), boolean()) :: outcome()
  def classify({:ok, %{status: status}}, retry_on_4xx), do: classify(status, retry_on_4xx)
  def classify({:error, _reason}, _retry_on_4xx), do: :retry
  def classify(status, _) when status in 200..299, do: :success
  def classify(status, _) when status in [408, 429], do: :retry
  def classify(status, _) when status in 500..599, do: :retry

  def classify(status, retry_on_4xx) when status in 400..499,
    do: if(retry_on_4xx, do: :retry, else: :give_up)

  def classify(status, _) when is_integer(status), do: :give_up

  @doc """
  Returns the delay in seconds before the attempt that follows attempt `n`
  (`n` ≥ 1).

  The delay is `1 + random(0, min(3600, 10 * 2^(n-1)))`. When `retry_after`
  (seconds) is given, the delay is at least `retry_after`, which is capped at
  3600. `rand` behaves like `:rand.uniform/1` (returns `1..k`) and can be
  injected to make the result deterministic.
  """
  @spec delay(pos_integer(), non_neg_integer() | nil, (pos_integer() -> pos_integer())) ::
          pos_integer()
  def delay(n, retry_after, rand \\ &:rand.uniform/1) when is_integer(n) and n >= 1 do
    # rand.(k + 1) - 1 is a uniform integer in 0..k.
    backoff = 1 + (rand.(max_jitter(n) + 1) - 1)

    case retry_after do
      nil -> backoff
      seconds when is_integer(seconds) -> max(backoff, min(seconds, @cap))
    end
  end

  defp max_jitter(n) do
    # Avoids computing huge powers of two for large attempt numbers.
    if n > 12, do: @cap, else: min(@cap, @base * Integer.pow(2, n - 1))
  end

  @doc """
  Parses a `Retry-After` header value into seconds from `now`.

  Accepts delta seconds (`"120"`) or an HTTP date
  (`"Wed, 21 Oct 2015 07:28:00 GMT"`); a date in the past gives `0`.
  Anything else returns `nil`.
  """
  @spec parse_retry_after(String.t() | nil, DateTime.t()) :: non_neg_integer() | nil
  def parse_retry_after(value, %DateTime{} = now) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> seconds
      {_, _} -> nil
      :error -> parse_http_date(value, now)
    end
  end

  def parse_retry_after(_value, _now), do: nil

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @http_date ~r/\A(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) (#{Enum.join(@months, "|")}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT\z/

  defp parse_http_date(value, now) do
    with [_, day, month, year, hour, minute, second] <- Regex.run(@http_date, value),
         {:ok, date} <- Date.new(to_int(year), month_number(month), to_int(day)),
         {:ok, time} <- Time.new(to_int(hour), to_int(minute), to_int(second)),
         {:ok, at} <- DateTime.new(date, time, "Etc/UTC") do
      max(DateTime.diff(at, now, :second), 0)
    else
      _ -> nil
    end
  end

  defp to_int(digits), do: String.to_integer(digits)

  defp month_number(name), do: Enum.find_index(@months, &(&1 == name)) + 1

  @doc """
  Schedules the next attempt `delay` seconds after `now`.

  Returns `{:retry_at, at}` when `at` is before `window_ends_at`, otherwise
  `:window_ended`.
  """
  @spec next(DateTime.t(), non_neg_integer(), DateTime.t()) ::
          {:retry_at, DateTime.t()} | :window_ended
  def next(%DateTime{} = now, delay, %DateTime{} = window_ends_at) when is_integer(delay) do
    at = DateTime.add(now, delay, :second)

    if DateTime.before?(at, window_ends_at), do: {:retry_at, at}, else: :window_ended
  end
end
