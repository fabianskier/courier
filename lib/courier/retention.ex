defmodule Courier.Retention do
  @moduledoc """
  Prunes old, finished events with their deliveries and attempts.

  An event is pruned when every delivery is terminal (not `pending`) and its
  last activity, the later of its insertion and its latest delivery
  completion, is older than the retention period. Pruning runs in batches,
  each in one transaction that sets `courier.retention = on` locally: this is
  the only place allowed to delete attempts.
  """

  import Ecto.Query

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Ingestion.Event
  alias Courier.Repo

  @default_days 30
  @min_days 2
  @batch_size 1_000
  @invalid_message "COURIER_RETENTION_DAYS must be a whole number of days, at least #{@min_days}"

  @type report :: %{
          events: non_neg_integer(),
          deliveries: non_neg_integer(),
          attempts: non_neg_integer(),
          batches: non_neg_integer()
        }

  @doc """
  Parses the value of `COURIER_RETENTION_DAYS`. Unset (`nil` or empty) means
  #{@default_days} days; anything that is not a whole number of at least
  #{@min_days} raises an `ArgumentError` naming the variable.
  """
  @spec parse_days(String.t() | nil) :: pos_integer()
  def parse_days(value) when value in [nil, ""], do: @default_days

  def parse_days(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} when days >= @min_days -> days
      _ -> raise ArgumentError, @invalid_message
    end
  end

  @doc """
  Deletes the events due for pruning with a period of `days`, batch by batch,
  and returns the rows deleted per table and the number of batches.

  Options: `:batch_size` (default #{@batch_size}) and `:now` (default
  `DateTime.utc_now/0`).
  """
  @spec prune(pos_integer(), keyword()) :: report()
  def prune(days, opts \\ []) when is_integer(days) and days > 0 do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    cutoff = DateTime.add(now, -days, :day)

    prune_batches(cutoff, batch_size, %{events: 0, deliveries: 0, attempts: 0, batches: 0})
  end

  defp prune_batches(cutoff, batch_size, report) do
    case prune_batch(cutoff, batch_size) do
      nil ->
        report

      counts ->
        report = %{
          events: report.events + counts.events,
          deliveries: report.deliveries + counts.deliveries,
          attempts: report.attempts + counts.attempts,
          batches: report.batches + 1
        }

        if counts.events < batch_size,
          do: report,
          else: prune_batches(cutoff, batch_size, report)
    end
  end

  # Selects and deletes one batch in a single transaction. Returns nil when
  # nothing is due.
  defp prune_batch(cutoff, batch_size) do
    {:ok, counts} =
      Repo.transaction(fn ->
        case Repo.all(due_events(cutoff, batch_size)) do
          [] -> nil
          event_ids -> delete_events(event_ids)
        end
      end)

    counts
  end

  defp due_events(cutoff, batch_size) do
    from e in Event,
      left_join: d in Delivery,
      on: d.event_id == e.id,
      group_by: e.id,
      having:
        fragment("bool_and(? IS NULL OR ? <> 'pending')", d.status, d.status) and
          fragment("greatest(?, max(?)) < ?", e.inserted_at, d.completed_at, ^cutoff),
      order_by: e.inserted_at,
      limit: ^batch_size,
      select: e.id
  end

  defp delete_events(event_ids) do
    Repo.query!("SET LOCAL courier.retention = 'on'")

    delivery_ids = from d in Delivery, where: d.event_id in ^event_ids, select: d.id

    {attempts, _} =
      Repo.delete_all(from a in Attempt, where: a.delivery_id in subquery(delivery_ids))

    deliveries = delete_deliveries(event_ids, 0)
    {events, _} = Repo.delete_all(from e in Event, where: e.id in ^event_ids)

    # Turn the exception off again so it never outlives the deletes, even when
    # this transaction is nested in an outer one.
    Repo.query!("SET LOCAL courier.retention = 'off'")

    %{events: events, deliveries: deliveries, attempts: attempts}
  end

  # A resend references the delivery it repeats (ON DELETE RESTRICT, checked
  # per row). Clearing `resend_of_id` would turn a resend into a second
  # original and break the unique index on originals, so each round deletes
  # the deliveries no other delivery points at, until none are left. Rounds
  # are bounded by the longest resend chain.
  defp delete_deliveries(event_ids, deleted) do
    {count, _} =
      Repo.delete_all(
        from d in Delivery,
          as: :delivery,
          where: d.event_id in ^event_ids,
          where:
            not exists(
              from r in Delivery,
                where: r.resend_of_id == parent_as(:delivery).id,
                select: 1
            )
      )

    if count == 0, do: deleted, else: delete_deliveries(event_ids, deleted + count)
  end
end
