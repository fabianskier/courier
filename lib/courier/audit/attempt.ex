defmodule Courier.Audit.Attempt do
  @moduledoc """
  One HTTP attempt to deliver a delivery to its endpoint.

  Attempts are append-only: the database rejects updates, and deletes outside
  the retention job, so this schema only has an insert changeset.
  `request_headers` never holds the signature (it is stored as `"[redacted]"`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]
  schema "attempts" do
    belongs_to :delivery, Courier.Delivery.Delivery

    field :number, :integer
    field :started_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :url, :string
    field :request_headers, :map, default: %{}
    field :response_status, :integer
    field :response_body, :string
    field :error, :string

    timestamps()
  end

  @doc """
  Changeset for a new attempt. All fields are set by the system, so `attrs`
  comes from internal code, never from request params.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(%__MODULE__{} = attempt, attrs) do
    attempt
    |> cast(attrs, [
      :delivery_id,
      :number,
      :started_at,
      :duration_ms,
      :url,
      :request_headers,
      :response_status,
      :response_body,
      :error
    ])
    |> validate_required([:delivery_id, :number, :started_at, :duration_ms, :url])
    |> validate_number(:number, greater_than: 0)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:delivery_id)
    |> unique_constraint([:delivery_id, :number])
  end
end
