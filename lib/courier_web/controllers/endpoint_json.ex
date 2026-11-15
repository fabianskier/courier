defmodule CourierWeb.EndpointJSON do
  @moduledoc """
  JSON rendering for endpoints: `{"data": ...}` for one endpoint and
  `{"data": [...], "next_cursor": ...}` for a page. Secrets are never rendered
  from the endpoint; only `show_with_secret/1` adds the `secret` it is given.
  """

  alias Courier.Endpoints.Endpoint

  @doc "Renders a page of endpoints."
  def index(%{page: %{items: items, next_cursor: next_cursor}}) do
    %{data: Enum.map(items, &data/1), next_cursor: next_cursor}
  end

  @doc "Renders one endpoint without its secret."
  def show(%{endpoint: endpoint}), do: %{data: data(endpoint)}

  @doc "Renders one endpoint with a just created or rotated `secret`."
  def show_with_secret(%{endpoint: endpoint, secret: secret}) when is_binary(secret) do
    %{data: Map.put(data(endpoint), :secret, secret)}
  end

  defp data(%Endpoint{} = endpoint) do
    %{
      id: endpoint.id,
      merchant_id: endpoint.merchant_id,
      url: endpoint.url,
      description: endpoint.description,
      event_types: endpoint.event_types,
      enabled: endpoint.enabled,
      retry_window_seconds: endpoint.retry_window_seconds,
      retry_on_4xx: endpoint.retry_on_4xx,
      max_concurrency: endpoint.max_concurrency,
      previous_secret_expires_at: iso8601(endpoint.previous_secret_expires_at),
      inserted_at: iso8601(endpoint.inserted_at),
      updated_at: iso8601(endpoint.updated_at)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
