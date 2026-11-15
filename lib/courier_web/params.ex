defmodule CourierWeb.Params do
  @moduledoc """
  Parsing of common query parameters for the JSON API.
  """

  @default_limit 50
  @max_limit 100

  @type pagination :: %{limit: pos_integer(), cursor: String.t() | nil}

  @doc """
  Parses `limit` (default #{@default_limit}, 1..#{@max_limit}) and `cursor`
  from request params. Returns `{:error, :invalid_pagination}` for bad values;
  the cursor's contents are checked later by `Courier.Pagination`.
  """
  @spec pagination(map()) :: {:ok, pagination()} | {:error, :invalid_pagination}
  def pagination(params) when is_map(params) do
    with {:ok, limit} <- parse_limit(Map.get(params, "limit")),
         {:ok, cursor} <- parse_cursor(Map.get(params, "cursor")) do
      {:ok, %{limit: limit, cursor: cursor}}
    end
  end

  defp parse_limit(nil), do: {:ok, @default_limit}

  defp parse_limit(limit) when is_integer(limit) and limit in 1..@max_limit, do: {:ok, limit}

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} -> parse_limit(value)
      _ -> {:error, :invalid_pagination}
    end
  end

  defp parse_limit(_limit), do: {:error, :invalid_pagination}

  defp parse_cursor(nil), do: {:ok, nil}
  defp parse_cursor(cursor) when is_binary(cursor) and cursor != "", do: {:ok, cursor}
  defp parse_cursor(_cursor), do: {:error, :invalid_pagination}
end
