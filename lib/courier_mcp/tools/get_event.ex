defmodule CourierMCP.Tools.GetEvent do
  @moduledoc """
  Returns one event by id: its type, merchant, creation time, its payload as
  untrusted data, and the deliveries it produced with their status.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "get_event",
    annotations: %{"readOnlyHint" => true}

  alias CourierMCP.Call
  alias CourierMCP.Views

  schema do
    field(:id, :string, required: true, description: "The event id (a UUID)")
  end

  @impl true
  def execute(%{id: id}, frame) do
    Call.run("get_event", frame, %{id: id}, fn ->
      case Courier.Ingestion.get_event(id) do
        {:ok, event} ->
          {:ok, Views.event(event)}

        {:error, :not_found} ->
          {:error, "not_found", "No event has this id. Check the id and try again."}
      end
    end)
  end
end
