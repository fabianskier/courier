defmodule Courier.EventsFixtures do
  @moduledoc """
  Test helpers for storing events directly, without the ingestion flow.
  """

  alias Courier.Ingestion.Event
  alias Courier.Repo

  @doc """
  Inserts an event and returns it. Creates a merchant unless `merchant_id` is
  given; defaults to type `payment.succeeded`, a small payload, a unique
  idempotency key and a random request hash.
  """
  def event_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new_lazy(:merchant_id, fn -> Courier.MerchantsFixtures.merchant_fixture().id end)
      |> Map.put_new(:type, "payment.succeeded")
      |> Map.put_new(:payload, %{"amount" => 1000, "currency" => "EUR"})

    event = %Event{
      idempotency_key:
        Map.get(attrs, :idempotency_key, "key-#{System.unique_integer([:positive])}"),
      request_hash: Map.get(attrs, :request_hash, :crypto.strong_rand_bytes(32)),
      received_at: Map.get(attrs, :received_at, DateTime.utc_now())
    }

    event
    |> Event.create_changeset(attrs)
    |> Repo.insert!()
  end
end
