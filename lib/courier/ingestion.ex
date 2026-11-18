defmodule Courier.Ingestion do
  @moduledoc """
  Event ingestion: validates an event, deduplicates it by idempotency key and
  stores it with one delivery per enabled endpoint of its merchant and one
  delivery job per pending delivery, all in one transaction.

  A repeat (same key, same `type`, `merchant_id`, `payload` and `occurred_at`
  as sent) returns the stored event; the same key with a different body is
  rejected. Key order inside `payload` does not matter. A repeat is answered
  even after the merchant was disabled. Deliveries are always listed by
  endpoint creation, then by delivery creation.
  """

  import Ecto.Query, warn: false

  alias Courier.Delivery.Delivery
  alias Courier.Delivery.{Queues, Worker}
  alias Courier.Endpoints.{Endpoint, EventFilter}
  alias Courier.Ingestion.Event
  alias Courier.Merchants.Merchant
  alias Courier.Pagination
  alias Courier.Repo
  alias Ecto.Multi

  @max_payload_bytes 262_144
  @key_format ~r/\A[\x21-\x7E]{1,255}\z/
  @event_fields ~w(idempotency_key request_hash merchant_id type payload occurred_at received_at)a

  @type error ::
          Ecto.Changeset.t()
          | :merchant_disabled
          | :payload_too_large
          | :idempotency_key_reused

  @doc """
  Ingests an event from `attrs` (`type`, `merchant_id`, `payload` and an
  optional `occurred_at`, with string or atom keys) under `idempotency_key`.

  Returns `{:ok, :created, event}` for a new event and `{:ok, :repeat, event}`
  for a repeat, with deliveries preloaded in both cases. A new event emits
  the telemetry event `[:courier, :event, :ingested]` and the notices
  `event_ingested` and one `delivery_changed` per delivery (see
  `Courier.Notices`) after commit; a repeat emits nothing.
  """
  @spec ingest(map(), String.t() | nil) ::
          {:ok, :created | :repeat, Event.t()} | {:error, error()}
  def ingest(attrs, idempotency_key) when is_map(attrs) do
    case ingest_multi(attrs, idempotency_key) do
      {:ok, multi} ->
        case Repo.transact(multi) do
          {:ok, %{event: event, deliveries: deliveries}} ->
            # After the transaction, so a rolled-back event emits nothing.
            Courier.Telemetry.emit_event_ingested(event, deliveries)
            Courier.Notices.event_ingested(event)
            Enum.each(deliveries, &Courier.Notices.delivery_changed/1)
            {:ok, :created, %{event | deliveries: deliveries}}

          {:error, :event, :duplicate, _changes} ->
            load_original(idempotency_key, request_hash(attrs))
        end

      # An event stored before the merchant was disabled is answered as for an
      # enabled merchant: a repeat or a reused key.
      {:error, :merchant_disabled} ->
        case Repo.get_by(Event, idempotency_key: idempotency_key) do
          nil -> {:error, :merchant_disabled}
          %Event{} = event -> compare_original(event, request_hash(attrs))
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Lists events newest first, one page at a time (see `Courier.Pagination`).
  With `merchant_id`, only that merchant's events (a malformed id matches
  none); with `type`, only events of exactly that type; with `since`
  (inclusive) and `until` (exclusive), `DateTime`s, only events received in
  that range (`received_at`). Deliveries are not loaded.
  """
  @spec list_events(%{
          required(:limit) => pos_integer(),
          optional(:cursor) => String.t() | nil,
          optional(:merchant_id) => String.t() | nil,
          optional(:type) => String.t() | nil,
          optional(:since) => DateTime.t() | nil,
          optional(:until) => DateTime.t() | nil
        }) :: {:ok, Pagination.page()} | {:error, :invalid_cursor}
  def list_events(opts) when is_map(opts) do
    Event
    |> filter_by_merchant(Map.get(opts, :merchant_id))
    |> filter_by_type(Map.get(opts, :type))
    |> filter_received_since(Map.get(opts, :since))
    |> filter_received_until(Map.get(opts, :until))
    |> Pagination.paginate(Map.put(opts, :order, :desc))
  end

  @doc """
  Returns the event with `id` and its deliveries (by endpoint creation), or
  `{:error, :not_found}` for unknown or malformed ids.
  """
  @spec get_event(term()) :: {:ok, Event.t()} | {:error, :not_found}
  def get_event(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Event{} = event <- Repo.get(Event, uuid) do
      {:ok, preload_deliveries(event)}
    else
      _ -> {:error, :not_found}
    end
  end

  defp filter_by_merchant(query, nil), do: query

  defp filter_by_merchant(query, merchant_id) do
    case Ecto.UUID.cast(merchant_id) do
      {:ok, uuid} -> where(query, [e], e.merchant_id == ^uuid)
      :error -> where(query, false)
    end
  end

  defp filter_by_type(query, nil), do: query
  defp filter_by_type(query, type) when is_binary(type), do: where(query, [e], e.type == ^type)
  defp filter_by_type(query, _type), do: where(query, false)

  defp filter_received_since(query, nil), do: query

  defp filter_received_since(query, %DateTime{} = since),
    do: where(query, [e], e.received_at >= ^since)

  defp filter_received_until(query, nil), do: query

  defp filter_received_until(query, %DateTime{} = until),
    do: where(query, [e], e.received_at < ^until)

  defp preload_deliveries(event) do
    Repo.preload(event,
      deliveries:
        from(d in Delivery,
          join: e in assoc(d, :endpoint),
          order_by: [asc: e.inserted_at, asc: e.id, asc: d.inserted_at, asc: d.id]
        )
    )
  end

  @doc false
  # Validates the event and returns the `Ecto.Multi` that stores it with its
  # deliveries and their jobs. Public so tests can append a failing step and prove atomicity.
  @spec ingest_multi(map(), String.t() | nil) :: {:ok, Multi.t()} | {:error, error()}
  def ingest_multi(attrs, idempotency_key) when is_map(attrs) do
    event = %Event{
      idempotency_key: idempotency_key,
      request_hash: request_hash(attrs),
      received_at: DateTime.utc_now()
    }

    changeset =
      event
      |> Event.create_changeset(normalize(attrs))
      |> validate_idempotency_key()

    with :ok <- check_valid(changeset),
         :ok <- check_payload_size(Ecto.Changeset.get_field(changeset, :payload)),
         :ok <- check_merchant(changeset) do
      multi =
        Multi.new()
        |> Multi.run(:event, fn repo, _changes -> insert_event(repo, changeset) end)
        |> Multi.run(:deliveries, fn repo, %{event: event} -> insert_deliveries(repo, event) end)
        |> Oban.insert_all(:jobs, fn %{deliveries: deliveries} -> delivery_jobs(deliveries) end)

      {:ok, multi}
    end
  end

  defp normalize(attrs) do
    Map.new([:type, :merchant_id, :payload, :occurred_at], &{&1, fetch_attr(attrs, &1)})
  end

  defp fetch_attr(attrs, field), do: Map.get(attrs, Atom.to_string(field), Map.get(attrs, field))

  # `:deterministic` makes the encoding independent of map key order.
  defp request_hash(attrs) do
    term = {
      fetch_attr(attrs, :type),
      fetch_attr(attrs, :merchant_id),
      fetch_attr(attrs, :payload),
      fetch_attr(attrs, :occurred_at)
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic]))
  end

  defp validate_idempotency_key(changeset) do
    key = Ecto.Changeset.get_field(changeset, :idempotency_key)

    cond do
      Keyword.has_key?(changeset.errors, :idempotency_key) ->
        changeset

      is_binary(key) and Regex.match?(@key_format, key) ->
        changeset

      true ->
        Ecto.Changeset.add_error(
          changeset,
          :idempotency_key,
          "must be 1 to 255 printable ASCII characters"
        )
    end
  end

  defp check_valid(%Ecto.Changeset{valid?: true}), do: :ok
  defp check_valid(changeset), do: {:error, %{changeset | action: :insert}}

  defp check_payload_size(payload) do
    if IO.iodata_length(Jason.encode_to_iodata!(payload)) > @max_payload_bytes,
      do: {:error, :payload_too_large},
      else: :ok
  end

  # `:binary_id` casts any string, so a malformed id is treated as unknown here.
  defp check_merchant(changeset) do
    merchant =
      case Ecto.UUID.cast(Ecto.Changeset.get_field(changeset, :merchant_id)) do
        {:ok, id} -> Repo.get(Merchant, id)
        :error -> nil
      end

    case merchant do
      %Merchant{enabled: true} ->
        :ok

      %Merchant{enabled: false} ->
        {:error, :merchant_disabled}

      nil ->
        changeset
        |> Ecto.Changeset.add_error(:merchant_id, "does not exist")
        |> check_valid()
    end
  end

  # `ON CONFLICT DO NOTHING` waits for a concurrent insert of the same key to
  # commit and then inserts nothing, so the loser sees the winner's event.
  defp insert_event(repo, changeset) do
    now = DateTime.utc_now()

    row =
      changeset
      |> Ecto.Changeset.apply_changes()
      |> Map.take(@event_fields)
      |> Map.merge(%{id: Ecto.UUID.generate(), inserted_at: now, updated_at: now})

    case repo.insert_all(Event, [row],
           on_conflict: :nothing,
           conflict_target: :idempotency_key,
           returning: true
         ) do
      {1, [event]} -> {:ok, event}
      {0, []} -> {:error, :duplicate}
    end
  end

  defp insert_deliveries(repo, %Event{} = event) do
    now = DateTime.utc_now()

    endpoints =
      repo.all(
        from e in Endpoint,
          where: e.merchant_id == ^event.merchant_id and e.enabled,
          order_by: [asc: e.inserted_at, asc: e.id],
          select: map(e, [:id, :event_types, :retry_window_seconds])
      )

    rows = Enum.map(endpoints, &delivery_row(&1, event, now))
    {_count, deliveries} = repo.insert_all(Delivery, rows, returning: true)

    # `RETURNING` does not promise the insert order; keep the endpoints' order.
    position = endpoints |> Enum.with_index() |> Map.new(fn {e, i} -> {e.id, i} end)
    {:ok, Enum.sort_by(deliveries, &Map.fetch!(position, &1.endpoint_id))}
  end

  defp delivery_jobs(deliveries) do
    for %Delivery{status: "pending"} = delivery <- deliveries do
      Worker.new(%{delivery_id: delivery.id}, queue: Queues.name(delivery.endpoint_id))
    end
  end

  defp delivery_row(endpoint, event, now) do
    base = %{
      id: Ecto.UUID.generate(),
      event_id: event.id,
      endpoint_id: endpoint.id,
      attempt_count: 0,
      triggered_by: "system",
      inserted_at: now,
      updated_at: now
    }

    if EventFilter.matches?(endpoint.event_types, event.type) do
      Map.merge(base, %{
        status: "pending",
        window_ends_at: DateTime.add(event.received_at, endpoint.retry_window_seconds, :second),
        completed_at: nil
      })
    else
      Map.merge(base, %{status: "skipped", window_ends_at: nil, completed_at: event.received_at})
    end
  end

  defp load_original(idempotency_key, request_hash) do
    Event
    |> Repo.get_by!(idempotency_key: idempotency_key)
    |> compare_original(request_hash)
  end

  defp compare_original(%Event{} = event, request_hash) do
    if event.request_hash == request_hash,
      do: {:ok, :repeat, preload_deliveries(event)},
      else: {:error, :idempotency_key_reused}
  end
end
