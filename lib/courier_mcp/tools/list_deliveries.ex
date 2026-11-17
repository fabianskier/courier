defmodule CourierMCP.Tools.ListDeliveries do
  @moduledoc """
  Lists deliveries newest first, without their attempts, optionally filtered
  by status, endpoint and event. Returns at most `limit` deliveries and a
  `next_cursor` when more exist; pass it as `cursor` to get the next page.
  Use get_delivery for the attempts of one delivery.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "list_deliveries",
    annotations: %{"readOnlyHint" => true}

  alias CourierMCP.Call
  alias CourierMCP.Views

  @filters [:status, :endpoint_id, :event_id, :limit, :cursor]

  schema do
    field(:status, {:enum, ["pending", "skipped", "succeeded", "failed"]},
      description: "Only deliveries with this status"
    )

    field(:endpoint_id, :string, description: "Only deliveries to this endpoint (a UUID)")
    field(:event_id, :string, description: "Only deliveries of this event (a UUID)")

    field(:limit, :integer,
      min: 1,
      max: 50,
      description: "Deliveries per call, 1 to 50 (default 20)"
    )

    field(:cursor, :string, description: "The next_cursor of a previous call")
  end

  @impl true
  def execute(params, frame) do
    args = args(params, @filters)
    Call.run("list_deliveries", frame, args, fn -> list(args) end)
  end

  @doc "The given `keys` of `params` that have a value: the call's arguments."
  @spec args(map(), [atom()]) :: map()
  def args(params, keys) do
    params
    |> Map.take(keys)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc "Lists deliveries with `filters` as a tool result."
  @spec list(map()) :: Call.result()
  def list(filters) do
    case Courier.Delivery.list_deliveries(filters) do
      {:ok, page} ->
        {:ok, Views.delivery_page(page)}

      {:error, :invalid_cursor} ->
        {:error, "invalid_cursor",
         "The cursor is not valid. Use the next_cursor of a previous call with the same " <>
           "filters, or omit it to start from the newest."}
    end
  end
end
