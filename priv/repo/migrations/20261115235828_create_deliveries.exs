defmodule Courier.Repo.Migrations.CreateDeliveries do
  use Ecto.Migration

  def change do
    create table(:deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :event_id, references(:events, type: :binary_id, on_delete: :restrict), null: false

      add :endpoint_id, references(:endpoints, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :window_ends_at, :utc_datetime_usec
      add :next_attempt_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :resend_of_id, references(:deliveries, type: :binary_id, on_delete: :restrict)
      add :triggered_by, :string, null: false, default: "system"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:deliveries, [:event_id, :endpoint_id],
             where: "resend_of_id IS NULL",
             name: :deliveries_event_id_endpoint_id_original_index
           )

    create index(:deliveries, [:endpoint_id, :status])
    create index(:deliveries, [:resend_of_id])

    create constraint(:deliveries, :status_values,
             check: "status IN ('pending','skipped','succeeded','failed')"
           )
  end
end
