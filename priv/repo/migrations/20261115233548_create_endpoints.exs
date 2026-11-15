defmodule Courier.Repo.Migrations.CreateEndpoints do
  use Ecto.Migration

  def change do
    create table(:endpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :merchant_id, references(:merchants, type: :binary_id, on_delete: :restrict),
        null: false

      add :url, :text, null: false
      add :description, :text
      add :event_types, {:array, :string}, null: false, default: []
      add :enabled, :boolean, null: false, default: true
      add :retry_window_seconds, :integer, null: false, default: 86_400
      add :retry_on_4xx, :boolean, null: false, default: false
      add :max_concurrency, :integer, null: false, default: 10
      add :secret, :binary, null: false
      add :previous_secret, :binary
      add :previous_secret_expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:endpoints, [:merchant_id])
    create index(:endpoints, [:inserted_at, :id])

    create constraint(:endpoints, :retry_window_seconds_range,
             check: "retry_window_seconds BETWEEN 60 AND 86400"
           )

    create constraint(:endpoints, :max_concurrency_range,
             check: "max_concurrency BETWEEN 1 AND 50"
           )
  end
end
