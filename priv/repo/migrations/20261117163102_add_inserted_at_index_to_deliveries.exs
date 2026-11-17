defmodule Courier.Repo.Migrations.AddInsertedAtIndexToDeliveries do
  use Ecto.Migration

  def change do
    create index(:deliveries, [:inserted_at, :id])
  end
end
