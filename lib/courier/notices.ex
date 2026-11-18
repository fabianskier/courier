defmodule Courier.Notices do
  @moduledoc """
  Change notices for the dashboard, broadcast over `Courier.PubSub` after a
  change is committed.

  Each notice is published on `"notices:<resource>"` as
  `{:notice, name, payload}`:

    * `"event_ingested"` on `"notices:events"`: `id`, `merchant_id`, `type`;
    * `"delivery_changed"` on `"notices:deliveries"`: `id`, `event_id`,
      `endpoint_id`, `status`;
    * `"endpoint_changed"` on `"notices:endpoints"`: `id`, `merchant_id`;
    * `"merchant_changed"` on `"notices:merchants"`: `id`.

  Payloads are maps with string keys and carry only ids, a status or a type,
  never payloads, response bodies, URLs, secrets or tokens. Callers invoke
  these functions only after their transaction commits, so a rolled-back
  change is never announced.
  """

  alias Courier.Delivery.Delivery
  alias Courier.Endpoints.Endpoint
  alias Courier.Ingestion.Event
  alias Courier.Merchants.Merchant

  @pubsub Courier.PubSub

  @doc "Returns the PubSub topic of a resource's notices."
  @spec topic(:events | :deliveries | :endpoints | :merchants) :: String.t()
  def topic(resource) when resource in [:events, :deliveries, :endpoints, :merchants],
    do: "notices:#{resource}"

  @doc "Announces a new event."
  @spec event_ingested(Event.t()) :: :ok
  def event_ingested(%Event{} = event) do
    broadcast(:events, "event_ingested", %{
      "id" => event.id,
      "merchant_id" => event.merchant_id,
      "type" => event.type
    })
  end

  @doc "Announces a created or changed delivery."
  @spec delivery_changed(Delivery.t()) :: :ok
  def delivery_changed(%Delivery{} = delivery) do
    broadcast(:deliveries, "delivery_changed", %{
      "id" => delivery.id,
      "event_id" => delivery.event_id,
      "endpoint_id" => delivery.endpoint_id,
      "status" => delivery.status
    })
  end

  @doc "Announces a created or changed endpoint."
  @spec endpoint_changed(Endpoint.t()) :: :ok
  def endpoint_changed(%Endpoint{} = endpoint) do
    broadcast(:endpoints, "endpoint_changed", %{
      "id" => endpoint.id,
      "merchant_id" => endpoint.merchant_id
    })
  end

  @doc "Announces a created or changed merchant."
  @spec merchant_changed(Merchant.t()) :: :ok
  def merchant_changed(%Merchant{} = merchant) do
    broadcast(:merchants, "merchant_changed", %{"id" => merchant.id})
  end

  defp broadcast(resource, name, payload) do
    # Notices are hints: a failed broadcast must not fail the committed change.
    _ = Phoenix.PubSub.broadcast(@pubsub, topic(resource), {:notice, name, payload})
    :ok
  end
end
