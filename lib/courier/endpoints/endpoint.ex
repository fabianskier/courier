defmodule Courier.Endpoints.Endpoint do
  @moduledoc """
  A merchant's HTTPS endpoint that receives webhooks.

  Secrets are encrypted at rest (`Courier.Encrypted.Binary`), set
  programmatically (never cast from params) and left out of `inspect/1`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Courier.Endpoints.{EventFilter, URLPolicy}

  @type t :: %__MODULE__{}

  @update_fields ~w(url description event_types enabled retry_window_seconds retry_on_4xx max_concurrency)a

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

  @doc "Changeset for a new, always enabled endpoint with the given `secret`."
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
    |> update_change(:url, &(&1 && String.trim(&1)))
    |> validate_required(@update_fields -- [:description])
    |> validate_length(:url, max: 2048)
    |> validate_change(:url, fn :url, url ->
      if URLPolicy.check(url) == :ok, do: [], else: [url: "must be a public https URL"]
    end)
    |> validate_length(:description, max: 1024)
    |> update_change(:event_types, &Enum.uniq/1)
    |> validate_length(:event_types, max: 50)
    |> validate_change(:event_types, fn :event_types, patterns ->
      if Enum.all?(patterns, &EventFilter.valid_pattern?/1),
        do: [],
        else: [event_types: "has an invalid pattern"]
    end)
    |> validate_number(:retry_window_seconds,
      greater_than_or_equal_to: 60,
      less_than_or_equal_to: 86_400
    )
    |> validate_number(:max_concurrency, greater_than_or_equal_to: 1, less_than_or_equal_to: 50)
    |> check_constraint(:retry_window_seconds, name: :retry_window_seconds_range)
    |> check_constraint(:max_concurrency, name: :max_concurrency_range)
  end
end
