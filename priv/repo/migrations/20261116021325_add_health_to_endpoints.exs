defmodule Courier.Repo.Migrations.AddHealthToEndpoints do
  use Ecto.Migration

  def change do
    alter table(:endpoints) do
      add :consecutive_failures, :integer, null: false, default: 0
      add :degraded_at, :utc_datetime_usec
    end

    create index(:endpoints, [:degraded_at], where: "degraded_at IS NOT NULL")
  end
end
