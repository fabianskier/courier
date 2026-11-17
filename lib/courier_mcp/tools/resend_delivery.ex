defmodule CourierMCP.Tools.ResendDelivery do
  @moduledoc """
  Changes state: resends a finished delivery (succeeded, failed or skipped)
  as a new pending delivery of the same event to the same endpoint, linked to
  it by resend_of_id. The original delivery and its attempts are not changed.
  Needs an API key with the write scope. Returns the new delivery and the id
  of the one it resends. Check the delivery with get_delivery first.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "resend_delivery",
    annotations: %{"readOnlyHint" => false, "destructiveHint" => false}

  alias Courier.Access
  alias CourierMCP.Call
  alias CourierMCP.Views

  schema do
    field(:id, :string, required: true, description: "The id of the delivery to resend (a UUID)")
  end

  @impl true
  def execute(%{id: id}, frame) do
    Call.run("resend_delivery", frame, %{id: id}, fn ->
      key = frame.assigns.current_key

      if Access.has_scope?(key, :write) do
        id |> Courier.Delivery.resend("api_key:" <> key.name) |> result()
      else
        {:error, "forbidden",
         "This API key cannot resend deliveries: it needs the write scope. Ask an operator."}
      end
    end)
  end

  defp result({:ok, resend}), do: {:ok, Views.resend(resend)}

  defp result({:error, :not_found}),
    do:
      {:error, "not_found",
       "No delivery has this id. Check the id, or find it with list_deliveries."}

  defp result({:error, :delivery_in_progress}),
    do:
      {:error, "delivery_in_progress",
       "The delivery is still pending: wait until it succeeds or fails, then resend it."}

  defp result({:error, :resend_in_progress}),
    do:
      {:error, "resend_in_progress",
       "The delivery already has a pending resend: follow it with get_delivery instead."}

  defp result({:error, :endpoint_disabled}),
    do:
      {:error, "endpoint_disabled",
       "The delivery's endpoint is disabled: it must be enabled before resending."}

  defp result({:error, %Ecto.Changeset{}}),
    do: {:error, "invalid", "The resend could not be created. Try again later."}
end
