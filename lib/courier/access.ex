defmodule Courier.Access do
  @moduledoc """
  API keys with scopes: creation, listing, revocation, authentication and
  scope checks.

  Tokens are `"ck_"` followed by 32 random bytes encoded as URL-safe base64.
  Only their SHA-256 hash is stored, and authentication looks keys up by that
  hash, so secrets are never compared in application code.
  """

  import Ecto.Query, warn: false

  alias Courier.Access.ApiKey
  alias Courier.Repo

  @token_prefix "ck_"
  @token_bytes 32

  @doc """
  Creates a key from `name` and `scopes`.

  Returns the key and its plaintext token. The token is shown only here and
  cannot be recovered later.
  """
  @spec create_key(map()) ::
          {:ok, %{key: ApiKey.t(), token: String.t()}} | {:error, Ecto.Changeset.t()}
  def create_key(attrs) when is_map(attrs) do
    token = generate_token()

    %ApiKey{}
    |> ApiKey.create_changeset(attrs, hash_token(token))
    |> Repo.insert()
    |> case do
      {:ok, key} -> {:ok, %{key: key, token: token}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Lists all keys, active and revoked, oldest first."
  @spec list_keys() :: [ApiKey.t()]
  def list_keys do
    ApiKey
    |> order_by([k], asc: k.inserted_at, asc: k.name)
    |> Repo.all()
  end

  @doc """
  Revokes the key named `name`.

  Revoking an already revoked key keeps its original `revoked_at`.
  """
  @spec revoke_key(String.t()) :: {:ok, ApiKey.t()} | {:error, :not_found}
  def revoke_key(name) when is_binary(name) do
    case Repo.get_by(ApiKey, name: name) do
      nil ->
        {:error, :not_found}

      %ApiKey{revoked_at: %DateTime{}} = key ->
        {:ok, key}

      %ApiKey{} = key ->
        key
        |> ApiKey.revoke_changeset(DateTime.utc_now())
        |> Repo.update()
    end
  end

  @doc "Returns the active key that owns `token`."
  @spec authenticate(term()) :: {:ok, ApiKey.t()} | {:error, :unauthorized}
  def authenticate(@token_prefix <> _ = token) do
    hash = hash_token(token)

    ApiKey
    |> where([k], k.token_hash == ^hash and is_nil(k.revoked_at))
    |> Repo.one()
    |> case do
      %ApiKey{} = key -> {:ok, key}
      nil -> {:error, :unauthorized}
    end
  end

  def authenticate(_token), do: {:error, :unauthorized}

  @doc "Whether `key` holds `scope` (an atom or string). Scopes are independent."
  @spec has_scope?(ApiKey.t(), atom() | String.t()) :: boolean()
  def has_scope?(%ApiKey{scopes: scopes}, scope) when is_atom(scope),
    do: Atom.to_string(scope) in scopes

  def has_scope?(%ApiKey{scopes: scopes}, scope) when is_binary(scope), do: scope in scopes

  defp generate_token do
    @token_prefix <> Base.url_encode64(:crypto.strong_rand_bytes(@token_bytes), padding: false)
  end

  defp hash_token(token), do: :crypto.hash(:sha256, token)
end
