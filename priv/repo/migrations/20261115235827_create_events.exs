defmodule Courier.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :idempotency_key, :string, null: false
      add :request_hash, :binary, null: false

      add :merchant_id, references(:merchants, type: :binary_id, on_delete: :restrict),
        null: false

      add :type, :string, null: false
      add :payload, :map, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :received_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:events, [:idempotency_key])
    create index(:events, [:merchant_id, :inserted_at])
    create index(:events, [:type])
    create index(:events, [:inserted_at, :id])
  end
end
