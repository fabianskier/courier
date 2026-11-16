defmodule Courier.Delivery do
  @moduledoc """
  Records the outcome of delivery attempts.

  A delivery's status only moves forward, from `pending` to `succeeded` or
  `failed`. Every write locks the delivery row (`FOR UPDATE`) inside a short
  transaction, never held during the HTTP request, and does nothing when the
  delivery is no longer `pending`, so a late or duplicate result is ignored.
  """

  import Ecto.Query, warn: false

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Repo

  @type transition ::
          {:succeeded, DateTime.t()} | {:failed, DateTime.t()} | {:retry_at, DateTime.t()}

  @doc """
  Stores an attempt for a pending delivery and applies `transition` in one
  transaction.

  `attempt_attrs` (atom keys, set by the system) holds the attempt fields
  except `delivery_id` and `number`; the number is `attempt_count + 1`.

    * `{:succeeded, now}` / `{:failed, now}` set the status and `completed_at`
      and clear `next_attempt_at`.
    * `{:retry_at, at}` keeps the delivery `pending` and sets `next_attempt_at`.

  Returns `{:ok, %{delivery: delivery, attempt: attempt}}`, `{:ok, :stale}`
  when the delivery is not `pending` (nothing is stored), or
  `{:error, :not_found}` / `{:error, changeset}`.
  """
  @spec record_attempt(Ecto.UUID.t(), map(), transition()) ::
          {:ok, %{delivery: Delivery.t(), attempt: Attempt.t()}}
          | {:ok, :stale}
          | {:error, :not_found | Ecto.Changeset.t()}
  def record_attempt(delivery_id, attempt_attrs, transition) do
    Repo.transact(fn ->
      with {:ok, delivery} <- lock_pending(delivery_id),
           {:ok, attempt} <- insert_attempt(delivery, attempt_attrs),
           {:ok, delivery} <- apply_transition(delivery, transition, attempt.number) do
        {:ok, %{delivery: delivery, attempt: attempt}}
      end
    end)
    |> stale_as_ok()
  end

  @doc """
  Marks a pending delivery `failed` without storing an attempt, for when its
  retry window ended before another attempt could be made.

  Returns `{:ok, delivery}`, `{:ok, :stale}` when it is no longer `pending`,
  or `{:error, :not_found}`.
  """
  @spec fail_without_attempt(Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Delivery.t()} | {:ok, :stale} | {:error, :not_found | Ecto.Changeset.t()}
  def fail_without_attempt(delivery_id, now) do
    Repo.transact(fn ->
      with {:ok, delivery} <- lock_pending(delivery_id) do
        apply_transition(delivery, {:failed, now}, delivery.attempt_count)
      end
    end)
    |> stale_as_ok()
  end

  defp lock_pending(delivery_id) do
    query = from d in Delivery, where: d.id == ^delivery_id, lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> {:error, :not_found}
      %Delivery{status: "pending"} = delivery -> {:ok, delivery}
      %Delivery{} -> {:error, :stale}
    end
  end

  defp insert_attempt(%Delivery{} = delivery, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.merge(%{delivery_id: delivery.id, number: delivery.attempt_count + 1})

    %Attempt{}
    |> Attempt.create_changeset(attrs)
    |> Repo.insert()
  end

  defp apply_transition(%Delivery{} = delivery, transition, attempt_count) do
    delivery
    |> Ecto.Changeset.change([{:attempt_count, attempt_count} | transition_changes(transition)])
    |> Repo.update()
  end

  defp transition_changes({status, %DateTime{} = now}) when status in [:succeeded, :failed] do
    [status: Atom.to_string(status), completed_at: now, next_attempt_at: nil]
  end

  defp transition_changes({:retry_at, %DateTime{} = at}), do: [next_attempt_at: at]

  defp stale_as_ok({:error, :stale}), do: {:ok, :stale}
  defp stale_as_ok(result), do: result
end
