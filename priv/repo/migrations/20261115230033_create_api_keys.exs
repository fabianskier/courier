defmodule Courier.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :scopes, {:array, :string}, null: false
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_keys, [:name])
    create unique_index(:api_keys, [:token_hash])

    create constraint(:api_keys, :scopes_not_empty, check: "cardinality(scopes) > 0")
  end
end
