defmodule Courier.IngestionDeliveryTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Delivery.{Delivery, Queues, Worker}
  alias Courier.Ingestion
  alias Courier.Ingestion.Event
  alias Courier.Merchants

  setup do
    %{merchant: merchant_fixture()}
  end

  defp attrs(merchant, overrides \\ %{}) do
    Map.merge(
      %{
        "type" => "payment.succeeded",
        "merchant_id" => merchant.id,
        "payload" => %{"amount" => 1000, "currency" => "EUR"}
      },
      overrides
    )
  end

  defp new_key, do: "key-#{System.unique_integer([:positive])}"

  defp count(schema), do: Repo.aggregate(schema, :count)

  describe "Requirement: Events are stored atomically" do
    test "Scenario: Jobs stored with the event", %{merchant: merchant} do
      {payments, _} = endpoint_fixture(%{merchant_id: merchant.id, event_types: ["payment.*"]})
      {refunds, _} = endpoint_fixture(%{merchant_id: merchant.id, event_types: ["refund.*"]})

      assert {:ok, :created, event} = Ingestion.ingest(attrs(merchant), new_key())

      pending = Enum.find(event.deliveries, &(&1.endpoint_id == payments.id))
      skipped = Enum.find(event.deliveries, &(&1.endpoint_id == refunds.id))
      assert %Delivery{status: "pending"} = pending
      assert %Delivery{status: "skipped"} = skipped

      assert [job] = all_enqueued(worker: Worker)
      assert job.args == %{"delivery_id" => pending.id}
    end

    test "Scenario: Failure while storing jobs", %{merchant: merchant} do
      endpoint_fixture(%{merchant_id: merchant.id})
      endpoint_fixture(%{merchant_id: merchant.id})

      assert {:ok, multi} = Ingestion.ingest_multi(attrs(merchant), new_key())

      result =
        multi
        |> Ecto.Multi.run(:fail, fn _repo, _changes -> {:error, :storage_failed} end)
        |> Repo.transact()

      assert {:error, :fail, :storage_failed, %{deliveries: [_, _], jobs: [_, _]}} = result
      assert count(Event) == 0
      assert count(Delivery) == 0
      assert count(Oban.Job) == 0
    end
  end

  describe "Requirement: One queue per endpoint" do
    test "Scenario: Job in the endpoint's queue", %{merchant: merchant} do
      {endpoint, _} = endpoint_fixture(%{merchant_id: merchant.id})

      assert {:ok, :created, %Event{deliveries: [delivery]}} =
               Ingestion.ingest(attrs(merchant), new_key())

      assert_enqueued(
        worker: Worker,
        queue: Queues.name(endpoint.id),
        args: %{"delivery_id" => delivery.id}
      )
    end
  end

  describe "Requirement: Disabled merchants are rejected" do
    test "Scenario: Repeat after the merchant was disabled", %{merchant: merchant} do
      endpoint_fixture(%{merchant_id: merchant.id})
      key = new_key()

      assert {:ok, :created, original} = Ingestion.ingest(attrs(merchant), key)
      {:ok, merchant} = Merchants.update_merchant(merchant, %{enabled: false})

      assert {:ok, :repeat, repeat} = Ingestion.ingest(attrs(merchant), key)
      assert repeat.id == original.id
      assert Enum.map(repeat.deliveries, & &1.id) == Enum.map(original.deliveries, & &1.id)

      assert count(Event) == 1
      assert count(Delivery) == 1
      assert count(Oban.Job) == 1
    end

    test "a reused key after the merchant was disabled is rejected as reused",
         %{merchant: merchant} do
      key = new_key()

      assert {:ok, :created, _original} = Ingestion.ingest(attrs(merchant), key)
      {:ok, merchant} = Merchants.update_merchant(merchant, %{enabled: false})

      assert {:error, :idempotency_key_reused} =
               Ingestion.ingest(attrs(merchant, %{"payload" => %{"amount" => 1}}), key)

      assert count(Event) == 1
    end

    test "a new key for a disabled merchant is still rejected", %{merchant: merchant} do
      assert {:ok, :created, _original} = Ingestion.ingest(attrs(merchant), new_key())
      {:ok, merchant} = Merchants.update_merchant(merchant, %{enabled: false})

      assert {:error, :merchant_disabled} = Ingestion.ingest(attrs(merchant), new_key())
      assert count(Event) == 1
    end
  end

  describe "Requirement: Read events" do
    test "Scenario: Stable delivery order", %{merchant: merchant} do
      endpoint_ids =
        for _ <- 1..3 do
          {endpoint, _} = endpoint_fixture(%{merchant_id: merchant.id})
          endpoint.id
        end

      key = new_key()
      assert {:ok, :created, created} = Ingestion.ingest(attrs(merchant), key)
      assert Enum.map(created.deliveries, & &1.endpoint_id) == endpoint_ids

      assert {:ok, :repeat, repeat} = Ingestion.ingest(attrs(merchant), key)
      assert Enum.map(repeat.deliveries, & &1.endpoint_id) == endpoint_ids

      assert {:ok, read} = Ingestion.get_event(created.id)
      assert Enum.map(read.deliveries, & &1.endpoint_id) == endpoint_ids
      assert Enum.map(read.deliveries, & &1.id) == Enum.map(created.deliveries, & &1.id)
    end
  end
end
