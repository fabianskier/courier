defmodule Courier.Endpoints do
  @moduledoc """
  Merchant endpoints: creation, lookup, paginated listing and updates. Endpoints
  are never deleted. Secrets (`whsec_` + base64 of 32 random bytes) are only
  returned by `create_endpoint/1` and `rotate_secret/2`.
  """

  import Ecto.Query, warn: false

  alias Courier.Delivery.QueueManager
  alias Courier.Endpoints.Endpoint
  alias Courier.Merchants.Merchant
  alias Courier.Pagination
  alias Courier.Repo

  @secret_bytes 32
  # How long the previous secret keeps signing after a rotation.
  @overlap_seconds 24 * 60 * 60

  @doc """
  Creates an enabled endpoint for an existing merchant and starts its delivery
  queue; returns the endpoint and its secret.
  """
  @spec create_endpoint(map()) :: {:ok, Endpoint.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create_endpoint(attrs) when is_map(attrs) do
    secret = generate_secret()

    changeset =
      %Endpoint{}
      |> Endpoint.create_changeset(attrs, secret)
      |> validate_merchant_exists()

    # Ecto logs query parameters before Cloak encrypts them; never log the secret.
    with {:ok, endpoint} <- Repo.insert(changeset, log: false) do
      :ok = QueueManager.sync(endpoint)
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

  @doc """
  Updates an endpoint with the same validation as creation, then starts, scales
  or stops its delivery queue to match (see `Courier.Delivery.QueueManager`).
  """
  @spec update_endpoint(Endpoint.t(), map()) :: {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t()}
  def update_endpoint(%Endpoint{} = endpoint, attrs) when is_map(attrs) do
    with {:ok, endpoint} <- endpoint |> Endpoint.update_changeset(attrs) |> Repo.update() do
      :ok = QueueManager.sync(endpoint)
      {:ok, endpoint}
    end
  end

  @doc """
  Rotates the endpoint's signing secret and returns the endpoint and its new
  secret. The old secret keeps signing for #{div(@overlap_seconds, 3600)} hours after `now`;
  rotating again during that overlap replaces it with the then-current secret.

  The row is locked while rotating, so concurrent rotations never keep a stale
  secret as the previous one.
  """
  @spec rotate_secret(Endpoint.t(), DateTime.t()) ::
          {:ok, Endpoint.t(), String.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def rotate_secret(%Endpoint{id: id}, %DateTime{} = now \\ DateTime.utc_now()) do
    secret = generate_secret()
    expires_at = now |> DateTime.add(@overlap_seconds, :second) |> to_usec()

    Repo.transact(fn ->
      with %Endpoint{} = locked <-
             Repo.one(from e in Endpoint, where: e.id == ^id, lock: "FOR UPDATE"),
           # Ecto logs query parameters before Cloak encrypts them; never log
           # the new or previous secret.
           {:ok, endpoint} <-
             locked
             |> Endpoint.rotate_changeset(secret, expires_at)
             |> Repo.update(log: false) do
        {:ok, {endpoint, secret}}
      else
        nil -> {:error, :not_found}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> case do
      {:ok, {endpoint, secret}} -> {:ok, endpoint, secret}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the secrets that currently sign for the endpoint: `[secret]`, or
  `[secret, previous_secret]` while `now` is before the overlap's end.
  """
  @spec signing_secrets(Endpoint.t(), DateTime.t()) :: [String.t(), ...]
  def signing_secrets(
        %Endpoint{secret: secret} = endpoint,
        %DateTime{} = now \\ DateTime.utc_now()
      )
      when is_binary(secret) do
    case endpoint do
      %Endpoint{previous_secret: previous, previous_secret_expires_at: %DateTime{} = expires_at}
      when is_binary(previous) ->
        if DateTime.before?(now, expires_at), do: [secret, previous], else: [secret]

      _ ->
        [secret]
    end
  end

  defp to_usec(%DateTime{microsecond: {us, _}} = datetime), do: %{datetime | microsecond: {us, 6}}

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
