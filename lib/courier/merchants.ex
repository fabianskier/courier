defmodule Courier.Merchants do
  @moduledoc """
  Merchants: creation, lookup, paginated listing, renaming and enabling or
  disabling. Merchants are never deleted.
  """

  alias Courier.Merchants.Merchant
  alias Courier.Pagination
  alias Courier.Repo

  @doc "Creates an enabled merchant from `name`."
  @spec create_merchant(map()) :: {:ok, Merchant.t()} | {:error, Ecto.Changeset.t()}
  def create_merchant(attrs) when is_map(attrs) do
    %Merchant{}
    |> Merchant.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns the merchant with `id`, or `{:error, :not_found}` for unknown or malformed ids."
  @spec get_merchant(term()) :: {:ok, Merchant.t()} | {:error, :not_found}
  def get_merchant(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Merchant{} = merchant <- Repo.get(Merchant, uuid) do
      {:ok, merchant}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Lists merchants oldest first, one page at a time (see `Courier.Pagination`)."
  @spec list_merchants(%{
          required(:limit) => pos_integer(),
          optional(:cursor) => String.t() | nil
        }) :: {:ok, Pagination.page()} | {:error, :invalid_cursor}
  def list_merchants(opts), do: Pagination.paginate(Merchant, opts)

  @doc "Changes a merchant's `name` and/or `enabled` flag."
  @spec update_merchant(Merchant.t(), map()) ::
          {:ok, Merchant.t()} | {:error, Ecto.Changeset.t()}
  def update_merchant(%Merchant{} = merchant, attrs) when is_map(attrs) do
    merchant
    |> Merchant.update_changeset(attrs)
    |> Repo.update()
  end
end
