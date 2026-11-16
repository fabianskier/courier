defmodule Courier.Delivery.Queues do
  @moduledoc """
  Names of the per-endpoint Oban queues: each endpoint's deliveries run in
  `endpoint:<id>`, limited to the endpoint's `max_concurrency`.
  """

  @doc "Returns the Oban queue name for the endpoint with `endpoint_id`."
  @spec name(Ecto.UUID.t()) :: String.t()
  def name(endpoint_id) when is_binary(endpoint_id), do: "endpoint:" <> endpoint_id
end
