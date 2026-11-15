defmodule CourierWeb.MerchantJSON do
  @moduledoc """
  JSON rendering for merchants: `{"data": ...}` for one merchant and
  `{"data": [...], "next_cursor": ...}` for a page.
  """

  alias Courier.Merchants.Merchant

  @doc "Renders a page of merchants."
  def index(%{page: %{items: items, next_cursor: next_cursor}}) do
    %{data: Enum.map(items, &data/1), next_cursor: next_cursor}
  end

  @doc "Renders one merchant."
  def show(%{merchant: merchant}), do: %{data: data(merchant)}

  defp data(%Merchant{} = merchant) do
    %{
      id: merchant.id,
      name: merchant.name,
      enabled: merchant.enabled,
      inserted_at: DateTime.to_iso8601(merchant.inserted_at),
      updated_at: DateTime.to_iso8601(merchant.updated_at)
    }
  end
end
