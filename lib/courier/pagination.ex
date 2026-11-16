defmodule Courier.Pagination do
  @moduledoc """
  Keyset pagination on `(inserted_at, id)`, oldest first by default or newest
  first with `order: :desc`.

  The cursor is opaque to callers: URL-safe base64 of
  `"<inserted_at ISO 8601 usec>|<id>"` for the last item of a page. The query's
  schema must have `inserted_at` (`utc_datetime_usec`) and a binary `id`.
  """

  import Ecto.Query, warn: false

  alias Courier.Repo

  @type page :: %{items: [struct()], next_cursor: String.t() | nil}

  @doc """
  Returns up to `limit` rows of `query` after `cursor` (or from the start when
  `cursor` is nil) and the cursor of the next page, nil on the last page.
  """
  @spec paginate(Ecto.Queryable.t(), %{
          required(:limit) => pos_integer(),
          optional(:cursor) => String.t() | nil,
          optional(:order) => :asc | :desc
        }) :: {:ok, page()} | {:error, :invalid_cursor}
  def paginate(query, %{limit: limit} = opts) when is_integer(limit) and limit > 0 do
    order = Map.get(opts, :order, :asc)

    with {:ok, query} <- after_cursor(query, Map.get(opts, :cursor), order) do
      rows =
        query
        |> order_by([r], [{^order, r.inserted_at}, {^order, r.id}])
        |> limit(^(limit + 1))
        |> Repo.all()

      {items, rest} = Enum.split(rows, limit)
      next_cursor = if rest == [], do: nil, else: encode_cursor(List.last(items))

      {:ok, %{items: items, next_cursor: next_cursor}}
    end
  end

  defp after_cursor(query, nil, _order), do: {:ok, query}

  defp after_cursor(query, cursor, order) when is_binary(cursor) do
    case decode_cursor(cursor) do
      {:ok, inserted_at, id} -> {:ok, where(query, ^beyond(order, inserted_at, id))}
      :error -> {:error, :invalid_cursor}
    end
  end

  defp after_cursor(_query, _cursor, _order), do: {:error, :invalid_cursor}

  defp beyond(:asc, inserted_at, id) do
    dynamic([r], r.inserted_at > ^inserted_at or (r.inserted_at == ^inserted_at and r.id > ^id))
  end

  defp beyond(:desc, inserted_at, id) do
    dynamic([r], r.inserted_at < ^inserted_at or (r.inserted_at == ^inserted_at and r.id < ^id))
  end

  defp encode_cursor(%{inserted_at: inserted_at, id: id}) do
    Base.url_encode64(DateTime.to_iso8601(inserted_at) <> "|" <> id)
  end

  defp decode_cursor(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor),
         [timestamp, raw_id] <- String.split(decoded, "|"),
         {:ok, inserted_at, 0} <- DateTime.from_iso8601(timestamp),
         {:ok, id} <- Ecto.UUID.cast(raw_id) do
      {:ok, usec(inserted_at), id}
    else
      _ -> :error
    end
  end

  defp usec(%DateTime{microsecond: {value, _precision}} = datetime),
    do: %{datetime | microsecond: {value, 6}}
end
