defmodule Courier.Audit do
  @moduledoc """
  The audit trail of delivery attempts. Attempts are append-only (enforced by
  the `attempts_append_only()` trigger) and are written by
  `Courier.Delivery.record_attempt/3`.
  """

  import Ecto.Query, warn: false

  alias Courier.Audit.Attempt
  alias Courier.Repo

  @doc "Returns the attempts of a delivery ordered by `number`."
  @spec list_attempts(Ecto.UUID.t()) :: [Attempt.t()]
  def list_attempts(delivery_id) do
    Attempt
    |> where([a], a.delivery_id == ^delivery_id)
    |> order_by([a], asc: a.number)
    |> Repo.all()
  end
end
