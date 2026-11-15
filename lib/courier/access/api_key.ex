defmodule Courier.Access.ApiKey do
  @moduledoc """
  A named API key with scopes.

  Only the SHA-256 hash of the token is stored; the plaintext token never lives
  in this struct. `token_hash` is hidden from `inspect/1`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @scopes ~w(ingest read write)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          token_hash: binary() | nil,
          scopes: [String.t()] | nil,
          revoked_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @derive {Inspect, except: [:token_hash]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "api_keys" do
    field :name, :string
    field :token_hash, :binary, redact: true
    field :scopes, {:array, :string}, default: []
    field :revoked_at, :utc_datetime_usec

    timestamps()
  end

  @doc "The scopes a key may hold."
  @spec scopes() :: [String.t()]
  def scopes, do: @scopes

  @doc """
  Changeset for a new key. `token_hash` is set programmatically, never cast.
  """
  @spec create_changeset(t(), map(), binary()) :: Ecto.Changeset.t()
  def create_changeset(key, attrs, token_hash) do
    key
    |> cast(attrs, [:name, :scopes])
    |> put_change(:token_hash, token_hash)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :token_hash])
    |> validate_length(:name, max: 255)
    |> validate_scopes()
    |> unique_constraint(:name)
    |> unique_constraint(:token_hash)
    |> check_constraint(:scopes, name: :scopes_not_empty, message: "can't be empty")
  end

  @doc "Changeset that marks a key as revoked."
  @spec revoke_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def revoke_changeset(key, now), do: change(key, revoked_at: now)

  defp validate_scopes(changeset) do
    changeset =
      case get_field(changeset, :scopes) do
        scopes when scopes in [nil, []] -> add_error(changeset, :scopes, "can't be empty")
        _scopes -> changeset
      end

    changeset
    |> validate_subset(:scopes, @scopes, message: "must be one of: #{Enum.join(@scopes, ", ")}")
    |> update_change(:scopes, &Enum.uniq/1)
  end
end
