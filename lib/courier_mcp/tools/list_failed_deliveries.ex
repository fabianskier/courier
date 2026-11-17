defmodule CourierMCP.Tools.ListFailedDeliveries do
  @moduledoc """
  Lists the deliveries that failed (every attempt was used or the delivery
  window ended), newest first, without their attempts, optionally for one
  endpoint. Returns at most `limit` deliveries and a `next_cursor` when more
  exist. Use get_delivery to see why one failed.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "list_failed_deliveries",
    annotations: %{"readOnlyHint" => true}

  alias CourierMCP.Call
  alias CourierMCP.Tools.ListDeliveries

  @filters [:endpoint_id, :limit, :cursor]

  schema do
    field(:endpoint_id, :string, description: "Only deliveries to this endpoint (a UUID)")

    field(:limit, :integer,
      min: 1,
      max: 50,
      description: "Deliveries per call, 1 to 50 (default 20)"
    )

    field(:cursor, :string, description: "The next_cursor of a previous call")
  end

  @impl true
  def execute(params, frame) do
    args = ListDeliveries.args(params, @filters)

    Call.run("list_failed_deliveries", frame, args, fn ->
      args |> Map.put(:status, "failed") |> ListDeliveries.list()
    end)
  end
end
