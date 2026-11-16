defmodule Courier.Delivery.RecordAttemptTest do
  use Courier.DataCase, async: true

  import Courier.AuditFixtures

  alias Courier.Audit
  alias Courier.Delivery
  alias Courier.Delivery.Delivery, as: DeliveryRecord

  defp attempt_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        started_at: DateTime.utc_now(),
        duration_ms: 12,
        url: "https://hooks.public.test/courier",
        request_headers: %{"webhook-signature" => "[redacted]"},
        response_status: 500,
        response_body: "error"
      },
      overrides
    )
  end

  defp now, do: DateTime.utc_now()

  describe "record_attempt/3" do
    test "numbers attempts 1, 2, 3 and updates attempt_count" do
      delivery = delivery_fixture()
      retry_at = DateTime.add(now(), 60, :second)

      assert {:ok, %{attempt: %{number: 1}, delivery: %{attempt_count: 1}}} =
               Delivery.record_attempt(delivery.id, attempt_attrs(), {:retry_at, retry_at})

      assert {:ok, %{attempt: %{number: 2}, delivery: %{attempt_count: 2}}} =
               Delivery.record_attempt(delivery.id, attempt_attrs(), {:retry_at, retry_at})

      assert {:ok, %{attempt: %{number: 3}, delivery: %{attempt_count: 3}}} =
               Delivery.record_attempt(
                 delivery.id,
                 attempt_attrs(%{response_status: 200}),
                 {:succeeded, now()}
               )

      assert [1, 2, 3] = Enum.map(Audit.list_attempts(delivery.id), & &1.number)
      assert Repo.get!(DeliveryRecord, delivery.id).attempt_count == 3
    end

    test "succeeded sets completed_at and clears next_attempt_at" do
      delivery = delivery_fixture()

      {:ok, _} =
        Delivery.record_attempt(
          delivery.id,
          attempt_attrs(),
          {:retry_at, DateTime.add(now(), 60, :second)}
        )

      completed_at = now()

      assert {:ok, _} =
               Delivery.record_attempt(
                 delivery.id,
                 attempt_attrs(%{response_status: 200}),
                 {:succeeded, completed_at}
               )

      stored = Repo.get!(DeliveryRecord, delivery.id)
      assert stored.status == "succeeded"
      assert stored.completed_at == completed_at
      assert stored.next_attempt_at == nil
    end

    test "failed sets completed_at and clears next_attempt_at" do
      delivery = delivery_fixture()

      {:ok, _} =
        Delivery.record_attempt(
          delivery.id,
          attempt_attrs(),
          {:retry_at, DateTime.add(now(), 60, :second)}
        )

      completed_at = now()

      assert {:ok, _} =
               Delivery.record_attempt(
                 delivery.id,
                 attempt_attrs(%{response_status: 410}),
                 {:failed, completed_at}
               )

      stored = Repo.get!(DeliveryRecord, delivery.id)
      assert stored.status == "failed"
      assert stored.completed_at == completed_at
      assert stored.next_attempt_at == nil
      assert stored.attempt_count == 2
    end

    test "retry_at keeps the delivery pending and sets next_attempt_at" do
      delivery = delivery_fixture()
      retry_at = DateTime.add(now(), 90, :second)

      assert {:ok, %{attempt: attempt}} =
               Delivery.record_attempt(delivery.id, attempt_attrs(), {:retry_at, retry_at})

      assert attempt.delivery_id == delivery.id
      assert attempt.response_status == 500

      stored = Repo.get!(DeliveryRecord, delivery.id)
      assert stored.status == "pending"
      assert stored.next_attempt_at == retry_at
      assert stored.completed_at == nil
    end

    test "returns an error for an unknown delivery" do
      assert {:error, :not_found} =
               Delivery.record_attempt(Ecto.UUID.generate(), attempt_attrs(), {:failed, now()})
    end
  end

  describe "Requirement: Delivery status only moves forward" do
    test "Scenario: Late result ignored" do
      delivery = delivery_fixture()

      {:ok, _} =
        Delivery.record_attempt(
          delivery.id,
          attempt_attrs(%{response_status: 200}),
          {:succeeded, now()}
        )

      before = Repo.get!(DeliveryRecord, delivery.id)

      assert {:ok, :stale} =
               Delivery.record_attempt(delivery.id, attempt_attrs(), {:failed, now()})

      assert {:ok, :stale} =
               Delivery.record_attempt(
                 delivery.id,
                 attempt_attrs(),
                 {:retry_at, DateTime.add(now(), 60, :second)}
               )

      assert {:ok, :stale} = Delivery.fail_without_attempt(delivery.id, now())

      assert [%{number: 1}] = Audit.list_attempts(delivery.id)
      assert Repo.get!(DeliveryRecord, delivery.id) == before
    end
  end

  describe "fail_without_attempt/2" do
    test "marks a pending delivery failed without storing an attempt" do
      delivery = delivery_fixture()

      {:ok, _} =
        Delivery.record_attempt(
          delivery.id,
          attempt_attrs(),
          {:retry_at, DateTime.add(now(), 60, :second)}
        )

      failed_at = now()

      assert {:ok, %DeliveryRecord{status: "failed"}} =
               Delivery.fail_without_attempt(delivery.id, failed_at)

      stored = Repo.get!(DeliveryRecord, delivery.id)
      assert stored.status == "failed"
      assert stored.completed_at == failed_at
      assert stored.next_attempt_at == nil
      assert stored.attempt_count == 1
      assert length(Audit.list_attempts(delivery.id)) == 1
    end
  end
end
