defmodule Courier.Endpoints do
  @moduledoc """
  Merchant endpoints: creation with a signing secret, lookup, paginated listing
  (optionally for one merchant) and updates. Endpoints are never deleted.

  URLs are checked with `Courier.Endpoints.URLPolicy` and event-type patterns
  with `Courier.Endpoints.EventFilter`. Secrets follow the Standard Webhooks
  format (`whsec_` + base64 of 32 random bytes) and are only returned by
  `create_endpoint/1`.
  """

  import Ecto.Query, warn: false

  alias Courier.Endpoints.Endpoint
  alias Courier.Merchants.Merchant
  alias Courier.Pagination
  alias Courier.Repo

  @secret_bytes 32

  @doc """
  Creates an enabled endpoint for an existing merchant and returns it with its
  new signing secret.
  """
  @spec create_endpoint(map()) :: {:ok, Endpoint.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create_endpoint(attrs) when is_map(attrs) do
    secret = generate_secret()

    changeset =
      %Endpoint{}
      |> Endpoint.create_changeset(attrs, secret)
      |> validate_merchant_exists()

    with {:ok, endpoint} <- Repo.insert(changeset) do
      {:ok, endpoint, secret}
    end
  end

  @doc "Returns the endpoint with `id`, or `{:error, :not_found}` for unknown or malformed ids."
  @spec get_endpoint(term()) :: {:ok, Endpoint.t()} | {:error, :not_found}
  def get_endpoint(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Endpoint{} = endpoint <- Repo.get(Endpoint, uuid) do
      {:ok, endpoint}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Lists endpoints oldest first, one page at a time (see `Courier.Pagination`).
  With `merchant_id`, only that merchant's endpoints; a malformed id matches none.
  """
  @spec list_endpoints(%{
          required(:limit) => pos_integer(),
          optional(:cursor) => String.t() | nil,
          optional(:merchant_id) => String.t() | nil
        }) :: {:ok, Pagination.page()} | {:error, :invalid_cursor}
  def list_endpoints(opts) do
    opts
    |> Map.get(:merchant_id)
    |> filter_by_merchant(Endpoint)
    |> Pagination.paginate(opts)
  end

  @doc "Updates an endpoint with the same validation as creation."
  @spec update_endpoint(Endpoint.t(), map()) :: {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t()}
  def update_endpoint(%Endpoint{} = endpoint, attrs) when is_map(attrs) do
    endpoint
    |> Endpoint.update_changeset(attrs)
    |> Repo.update()
  end

  defp generate_secret do
    "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(@secret_bytes))
  end

  defp filter_by_merchant(nil, query), do: query

  defp filter_by_merchant(merchant_id, query) do
    case Ecto.UUID.cast(merchant_id) do
      {:ok, uuid} -> where(query, [e], e.merchant_id == ^uuid)
      :error -> where(query, false)
    end
  end

  # The foreign key constraint covers races; this check reports the common
  # case without relying on the database error.
  defp validate_merchant_exists(changeset) do
    Ecto.Changeset.validate_change(changeset, :merchant_id, fn :merchant_id, merchant_id ->
      with {:ok, uuid} <- Ecto.UUID.cast(merchant_id),
           true <- Repo.exists?(from m in Merchant, where: m.id == ^uuid) do
        []
      else
        _ -> [merchant_id: "does not exist"]
      end
    end)
  end
end
