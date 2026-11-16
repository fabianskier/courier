defmodule Courier.Delivery.Delivery do
  @moduledoc """
  The delivery of one event to one endpoint.

  Ingestion creates one original delivery (`resend_of_id` nil) per enabled
  endpoint: `pending` with a `window_ends_at`, or `skipped` with `completed_at`
  set to the receipt time. A resend is a new delivery pointing at the one it
  repeats, so only one original delivery may exist per event and endpoint.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(pending skipped succeeded failed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "deliveries" do
    belongs_to :event, Courier.Ingestion.Event
    belongs_to :endpoint, Courier.Endpoints.Endpoint
    belongs_to :resend_of, __MODULE__
    has_many :attempts, Courier.Audit.Attempt

    field :status, :string
    field :attempt_count, :integer, default: 0
    field :window_ends_at, :utc_datetime_usec
    field :next_attempt_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :triggered_by, :string, default: "system"

    timestamps()
  end

  @doc "The statuses a delivery can have."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc """
  Changeset for a new delivery. All fields are set by the system, so `attrs`
  comes from internal code, never from request params.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(%__MODULE__{} = delivery, attrs) do
    delivery
    |> cast(attrs, [
      :event_id,
      :endpoint_id,
      :resend_of_id,
      :status,
      :window_ends_at,
      :completed_at,
      :triggered_by
    ])
    |> validate_required([:event_id, :endpoint_id, :status, :triggered_by])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :status_values)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:endpoint_id)
    |> unique_constraint([:event_id, :endpoint_id],
      name: :deliveries_event_id_endpoint_id_original_index
    )
  end
end
