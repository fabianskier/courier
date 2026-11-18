defmodule CourierDemo.Load.Stats do
  @moduledoc """
  The statistics of the load report: nearest-rank percentiles and rates.

  Pure functions, so the numbers of the report can be checked without a run.
  """

  @doc """
  The `p`-th percentile of `values` by nearest rank: the `ceil(p / 100 * n)`-th
  smallest value (at least the first). Returns `nil` for an empty list.

      iex> CourierDemo.Load.Stats.percentile(Enum.to_list(1..100), 95)
      95
  """
  @spec percentile([number()], number()) :: number() | nil
  def percentile([], _p), do: nil

  def percentile(values, p) when p > 0 and p <= 100 do
    sorted = Enum.sort(values)
    rank = max(ceil(p / 100 * length(sorted)), 1)
    Enum.at(sorted, rank - 1)
  end

  @doc "`count` per second over `ms` milliseconds; `nil` when no time passed."
  @spec rate(non_neg_integer(), integer()) :: float() | nil
  def rate(_count, ms) when ms <= 0, do: nil
  def rate(count, ms), do: count * 1000 / ms

  @doc "A percentile in milliseconds for the report: `\"12 ms\"`, or `\"n/a\"`."
  @spec format_ms(number() | nil) :: String.t()
  def format_ms(nil), do: "n/a"
  def format_ms(ms), do: "#{round(ms)} ms"

  @doc "A rate for the report with one decimal: `\"50.0/s\"`, or `\"n/a\"`."
  @spec format_rate(float() | nil) :: String.t()
  def format_rate(nil), do: "n/a"
  def format_rate(rate), do: :erlang.float_to_binary(rate / 1, decimals: 1) <> "/s"
end
