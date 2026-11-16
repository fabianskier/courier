defmodule Courier.Endpoints.EventFilter do
  @moduledoc """
  Event-type patterns for endpoints.

  A pattern is either an exact type made of dot-separated lowercase segments
  (letters, digits, `_`), such as `payment.succeeded`, or such a prefix
  followed by `.*`, such as `payment.*`. A wildcard matches any type that
  starts with its prefix followed by a dot, so `payment.*` matches
  `payment.succeeded` and `payment.card.declined` but not `payments.created`.

  An empty pattern list matches every type.
  """

  @pattern ~r/\A[a-z0-9_]+(\.[a-z0-9_]+)*(\.\*)?\z/

  @doc """
  Returns true when `pattern` is a valid exact type or prefix wildcard.

  `*` alone, uppercase letters, inner wildcards and empty strings are invalid.
  """
  @spec valid_pattern?(term()) :: boolean()
  def valid_pattern?(pattern) when is_binary(pattern), do: Regex.match?(@pattern, pattern)
  def valid_pattern?(_pattern), do: false

  @type_pattern ~r/\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/

  @doc """
  Returns true when `type` is a valid event type: an exact pattern, without
  wildcard, such as `payment.succeeded`.
  """
  @spec valid_type?(term()) :: boolean()
  def valid_type?(type) when is_binary(type), do: Regex.match?(@type_pattern, type)
  def valid_type?(_type), do: false

  @doc """
  Returns true when `type` matches any of `patterns`, or when `patterns` is empty.
  """
  @spec matches?([String.t()], String.t()) :: boolean()
  def matches?([], type) when is_binary(type), do: true

  def matches?(patterns, type) when is_list(patterns) and is_binary(type) do
    Enum.any?(patterns, &pattern_matches?(&1, type))
  end

  defp pattern_matches?(pattern, type) do
    if String.ends_with?(pattern, ".*") do
      # Keep the trailing dot so `payment.*` does not match `payments.created`.
      prefix = binary_part(pattern, 0, byte_size(pattern) - 1)
      String.starts_with?(type, prefix)
    else
      pattern == type
    end
  end
end
