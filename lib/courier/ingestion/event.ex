defmodule Courier.Ingestion.Event do
  @moduledoc """
  An event accepted from the producer for one merchant.

  `idempotency_key`, `request_hash` and `received_at` are set programmatically
  (never cast from params). `occurred_at` defaults to `received_at`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Courier.Endpoints.EventFilter

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  schema "events" do
    belongs_to :merchant, Courier.Merchants.Merchant
    has_many :deliveries, Courier.Delivery.Delivery

    field :idempotency_key, :string
    field :request_hash, :binary, redact: true
    field :type, :string
    field :payload, :map
    field :occurred_at, :utc_datetime_usec
    field :received_at, :utc_datetime_usec

    timestamps()
  end

  @doc """
  Changeset for a new event from `attrs` (`type`, `merchant_id`, `payload`,
  `occurred_at`). The given `event` must already carry `idempotency_key`,
  `request_hash` and `received_at`.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(%__MODULE__{} = event, attrs) do
    event
    |> cast(attrs, [:type, :merchant_id, :payload, :occurred_at])
    |> validate_required([:type, :merchant_id, :payload])
    |> validate_length(:type, max: 255)
    |> validate_change(:type, fn :type, type ->
      if EventFilter.valid_type?(type), do: [], else: [type: "is not a valid event type"]
    end)
    |> default_occurred_at()
    |> validate_required([:idempotency_key, :request_hash, :received_at, :occurred_at])
    |> foreign_key_constraint(:merchant_id, message: "does not exist")
    |> unique_constraint(:idempotency_key)
  end

  defp default_occurred_at(changeset) do
    if get_field(changeset, :occurred_at) == nil and not has_error?(changeset, :occurred_at) do
      put_change(changeset, :occurred_at, get_field(changeset, :received_at))
    else
      changeset
    end
  end

  defp has_error?(changeset, field), do: Keyword.has_key?(changeset.errors, field)
end
