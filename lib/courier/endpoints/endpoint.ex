defmodule Courier.Endpoints.Endpoint do
  @moduledoc """
  A merchant's HTTPS endpoint that receives webhooks.

  Secrets are encrypted at rest (`Courier.Encrypted.Binary`), set
  programmatically (never cast from params) and left out of `inspect/1`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Courier.Endpoints.EventFilter
  alias Courier.Endpoints.URLPolicy

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          merchant_id: Ecto.UUID.t() | nil,
          url: String.t() | nil,
          description: String.t() | nil,
          event_types: [String.t()],
          enabled: boolean(),
          retry_window_seconds: pos_integer(),
          retry_on_4xx: boolean(),
          max_concurrency: pos_integer(),
          secret: String.t() | nil,
          previous_secret: String.t() | nil,
          previous_secret_expires_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @max_event_types 50
  @url_error "must be a public https URL"

  @update_fields [
    :url,
    :description,
    :event_types,
    :enabled,
    :retry_window_seconds,
    :retry_on_4xx,
    :max_concurrency
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]
  @derive {Inspect, except: [:secret, :previous_secret]}
  schema "endpoints" do
    belongs_to :merchant, Courier.Merchants.Merchant

    field :url, :string
    field :description, :string
    field :event_types, {:array, :string}, default: []
    field :enabled, :boolean, default: true
    field :retry_window_seconds, :integer, default: 86_400
    field :retry_on_4xx, :boolean, default: false
    field :max_concurrency, :integer, default: 10
    field :secret, Courier.Encrypted.Binary, redact: true
    field :previous_secret, Courier.Encrypted.Binary, redact: true
    field :previous_secret_expires_at, :utc_datetime_usec

    timestamps()
  end

  @doc """
  Changeset for a new endpoint. New endpoints are always enabled; `secret` is
  set by the caller, not cast.
  """
  @spec create_changeset(t(), map(), String.t()) :: Ecto.Changeset.t()
  def create_changeset(endpoint, attrs, secret) when is_binary(secret) do
    endpoint
    |> cast(attrs, [:merchant_id | @update_fields -- [:enabled]])
    |> validate_required([:merchant_id])
    |> put_change(:secret, secret)
    |> validate()
    |> foreign_key_constraint(:merchant_id, message: "does not exist")
  end

  @doc "Changeset to update an endpoint's URL, description, patterns, flag or settings."
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, @update_fields)
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> update_change(:url, &trim/1)
    |> validate_required([
      :url,
      :event_types,
      :enabled,
      :retry_window_seconds,
      :retry_on_4xx,
      :max_concurrency
    ])
    |> validate_length(:url, max: 2048)
    |> validate_change(:url, &validate_url/2)
    |> validate_length(:description, max: 1024)
    |> update_change(:event_types, &Enum.uniq/1)
    |> validate_length(:event_types, max: @max_event_types)
    |> validate_change(:event_types, &validate_event_types/2)
    |> validate_number(:retry_window_seconds,
      greater_than_or_equal_to: 60,
      less_than_or_equal_to: 86_400
    )
    |> validate_number(:max_concurrency, greater_than_or_equal_to: 1, less_than_or_equal_to: 50)
    |> check_constraint(:retry_window_seconds,
      name: :retry_window_seconds_range,
      message: "must be between 60 and 86400"
    )
    |> check_constraint(:max_concurrency,
      name: :max_concurrency_range,
      message: "must be between 1 and 50"
    )
  end

  defp validate_url(field, url) do
    case URLPolicy.check(url) do
      :ok -> []
      {:error, _reason} -> [{field, @url_error}]
    end
  end

  defp validate_event_types(field, patterns) do
    if Enum.all?(patterns, &EventFilter.valid_pattern?/1),
      do: [],
      else: [{field, "has an invalid pattern"}]
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
