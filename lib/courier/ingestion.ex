defmodule Courier.Ingestion do
  @moduledoc """
  Event ingestion: validates an event, deduplicates it by idempotency key and
  stores it with one delivery per enabled endpoint of its merchant, all in one
  transaction.

  A repeat (same key, same `type`, `merchant_id`, `payload` and `occurred_at`
  as sent) returns the stored event; the same key with a different body is
  rejected. Key order inside `payload` does not matter.
  """

  import Ecto.Query, warn: false

  alias Courier.Delivery.Delivery
  alias Courier.Endpoints.{Endpoint, EventFilter}
  alias Courier.Ingestion.Event
  alias Courier.Merchants.Merchant
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
  for a repeat, with deliveries preloaded in both cases.
  """
  @spec ingest(map(), String.t() | nil) ::
          {:ok, :created | :repeat, Event.t()} | {:error, error()}
  def ingest(attrs, idempotency_key) when is_map(attrs) do
    with {:ok, multi} <- ingest_multi(attrs, idempotency_key) do
      case Repo.transact(multi) do
        {:ok, %{event: event, deliveries: deliveries}} ->
          {:ok, :created, %{event | deliveries: deliveries}}

        {:error, :event, :duplicate, _changes} ->
          load_original(idempotency_key, request_hash(attrs))
      end
    end
  end

  @doc false
  # Validates the event and returns the `Ecto.Multi` that stores it with its
  # deliveries. Public so tests can append a failing step and prove atomicity.
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
    {:ok, deliveries}
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
    event =
      Event
      |> Repo.get_by!(idempotency_key: idempotency_key)
      |> Repo.preload(deliveries: from(d in Delivery, order_by: [asc: d.inserted_at, asc: d.id]))

    if event.request_hash == request_hash,
      do: {:ok, :repeat, event},
      else: {:error, :idempotency_key_reused}
  end
end
