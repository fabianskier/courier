defmodule Courier.Repo.Migrations.CreateAttempts do
  use Ecto.Migration

  def change do
    create table(:attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :delivery_id, references(:deliveries, type: :binary_id, on_delete: :restrict),
        null: false

      add :number, :integer, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :duration_ms, :integer, null: false
      add :url, :text, null: false
      add :request_headers, :map, null: false, default: %{}
      add :response_status, :integer
      add :response_body, :text
      add :error, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:attempts, [:delivery_id, :number])

    # Attempts are append-only: no UPDATE ever, and DELETE only when the
    # retention job sets `courier.retention` to `on` in its transaction.
    execute(
      """
      CREATE FUNCTION attempts_append_only() RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'UPDATE' THEN
          RAISE EXCEPTION 'attempts are append-only: UPDATE is not allowed';
        END IF;

        IF coalesce(current_setting('courier.retention', true), '') <> 'on' THEN
          RAISE EXCEPTION 'attempts are append-only: DELETE requires courier.retention = on';
        END IF;

        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql
      """,
      "DROP FUNCTION attempts_append_only()"
    )

    execute(
      """
      CREATE TRIGGER attempts_append_only
      BEFORE UPDATE OR DELETE ON attempts
      FOR EACH ROW EXECUTE FUNCTION attempts_append_only()
      """,
      "DROP TRIGGER attempts_append_only ON attempts"
    )
  end
end
