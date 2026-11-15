defmodule Courier.Merchants.Merchant do
  @moduledoc """
  A merchant whose events courier delivers. Merchants own endpoints and are
  never deleted; they are disabled instead.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          enabled: boolean() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "merchants" do
    field :name, :string
    field :enabled, :boolean, default: true

    timestamps()
  end

  @doc "Changeset for a new merchant. New merchants are always enabled."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(merchant, attrs) do
    merchant
    |> cast(attrs, [:name])
    |> validate_name()
  end

  @doc "Changeset to rename a merchant or change its enabled flag."
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(merchant, attrs) do
    merchant
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:enabled])
    |> validate_name()
  end

  defp validate_name(changeset) do
    changeset
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end

  defp trim(name) when is_binary(name), do: String.trim(name)
  defp trim(name), do: name
end
