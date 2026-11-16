defmodule Courier.IngestionTest do
  # Not async: "Simultaneous repeats" runs requests from several processes in
  # the sandbox's shared mode.
  use Courier.DataCase, async: false

  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Delivery.Delivery
  alias Courier.Endpoints
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
        "payload" => %{"amount" => 1000, "currency" => "EUR", "order" => %{"id" => "o-1"}}
      },
      overrides
    )
  end

  defp new_key, do: "key-#{System.unique_integer([:positive])}"

  defp count(schema), do: Repo.aggregate(schema, :count)

  defp assert_nothing_stored do
    assert count(Event) == 0
    assert count(Delivery) == 0
  end

  defp sorted_ids(deliveries), do: deliveries |> Enum.map(& &1.id) |> Enum.sort()

  describe "Requirement: Accept events" do
    test "Scenario: Occurrence time defaults to receipt", %{merchant: merchant} do
      assert {:ok, :created, event} = Ingestion.ingest(attrs(merchant), new_key())
      assert event.occurred_at == event.received_at

      stored = Repo.get!(Event, event.id)
      assert stored.occurred_at == stored.received_at
    end

    test "an explicit occurrence time is kept", %{merchant: merchant} do
      attrs = attrs(merchant, %{"occurred_at" => "2026-11-01T10:00:00Z"})

      assert {:ok, :created, event} = Ingestion.ingest(attrs, new_key())
      assert event.occurred_at == ~U[2026-11-01 10:00:00.000000Z]
      assert event.type == "payment.succeeded"
      assert event.merchant_id == merchant.id
      assert event.payload == attrs["payload"]
    end
  end

  describe "Requirement: Idempotency key is required" do
    test "Scenario: Missing key", %{merchant: merchant} do
      assert {:error, changeset} = Ingestion.ingest(attrs(merchant), nil)
      assert %{idempotency_key: [_ | _]} = errors_on(changeset)
      assert_nothing_stored()
    end

    test "Scenario: Malformed key", %{merchant: merchant} do
      for key <- ["", String.duplicate("k", 256), "has space", "naïve"] do
        assert {:error, changeset} = Ingestion.ingest(attrs(merchant), key)
        assert %{idempotency_key: [_ | _]} = errors_on(changeset)
      end

      assert {:ok, :created, _event} =
               Ingestion.ingest(attrs(merchant), String.duplicate("k", 255))

      assert count(Event) == 1
    end
  end

  describe "Requirement: Repeats return the original event" do
    test "Scenario: Exact repeat", %{merchant: merchant} do
      endpoint_fixture(%{merchant_id: merchant.id})
      key = new_key()

      assert {:ok, :created, original} = Ingestion.ingest(attrs(merchant), key)
      assert {:ok, :repeat, repeat} = Ingestion.ingest(attrs(merchant), key)

      assert repeat.id == original.id
      assert length(original.deliveries) == 1
      assert sorted_ids(repeat.deliveries) == sorted_ids(original.deliveries)
      assert count(Event) == 1
      assert count(Delivery) == 1
    end

    test "Scenario: Same payload with keys in another order", %{merchant: merchant} do
      key = new_key()
      first = attrs(merchant)

      reordered =
        attrs(merchant, %{
          "payload" =>
            Jason.decode!(~s({"order": {"id": "o-1"}, "currency": "EUR", "amount": 1000}))
        })

      assert {:ok, :created, original} = Ingestion.ingest(first, key)
      assert {:ok, :repeat, repeat} = Ingestion.ingest(reordered, key)
      assert repeat.id == original.id
      assert count(Event) == 1
    end
  end

  describe "Requirement: Reused keys are rejected" do
    test "Scenario: Key reused with a different body", %{merchant: merchant} do
      key = new_key()
      assert {:ok, :created, original} = Ingestion.ingest(attrs(merchant), key)

      different = attrs(merchant, %{"payload" => %{"amount" => 2000}})
      assert {:error, :idempotency_key_reused} = Ingestion.ingest(different, key)

      with_occurrence = attrs(merchant, %{"occurred_at" => "2026-11-01T10:00:00Z"})
      assert {:error, :idempotency_key_reused} = Ingestion.ingest(with_occurrence, key)

      assert count(Event) == 1
      assert Repo.get!(Event, original.id).payload == original.payload
    end
  end

  describe "Requirement: Concurrent duplicates store one event" do
    test "Scenario: Simultaneous repeats", %{merchant: merchant} do
      endpoint_fixture(%{merchant_id: merchant.id})
      key = new_key()
      attrs = attrs(merchant)

      results =
        1..5
        |> Task.async_stream(fn _ -> Ingestion.ingest(attrs, key) end, timeout: :infinity)
        |> Enum.map(fn {:ok, result} -> result end)

      ids = Enum.map(results, fn {:ok, _kind, event} -> event.id end)
      assert ids |> Enum.uniq() |> length() == 1
      assert Enum.count(results, &match?({:ok, :created, _}, &1)) == 1
      assert count(Event) == 1
      assert count(Delivery) == 1
    end
  end

  describe "Requirement: Validate events" do
    test "Scenario: Event for unknown merchant", %{merchant: merchant} do
      unknown = attrs(merchant, %{"merchant_id" => Ecto.UUID.generate()})
      assert {:error, changeset} = Ingestion.ingest(unknown, new_key())
      assert %{merchant_id: ["does not exist"]} = errors_on(changeset)

      malformed = attrs(merchant, %{"merchant_id" => "not-a-uuid"})
      assert {:error, changeset} = Ingestion.ingest(malformed, new_key())
      assert %{merchant_id: [_ | _]} = errors_on(changeset)

      assert_nothing_stored()
    end

    test "Scenario: Invalid type or payload", %{merchant: merchant} do
      assert {:error, changeset} =
               Ingestion.ingest(attrs(merchant, %{"type" => "Payment Succeeded"}), new_key())

      assert %{type: [_ | _]} = errors_on(changeset)

      for payload <- [[1, 2], "a string"] do
        assert {:error, changeset} =
                 Ingestion.ingest(attrs(merchant, %{"payload" => payload}), new_key())

        assert %{payload: [_ | _]} = errors_on(changeset)
      end

      assert {:error, changeset} =
               Ingestion.ingest(attrs(merchant, %{"occurred_at" => "yesterday"}), new_key())

      assert %{occurred_at: [_ | _]} = errors_on(changeset)

      assert_nothing_stored()
    end
  end

  describe "Requirement: Disabled merchants are rejected" do
    test "Scenario: Merchant disabled", %{merchant: merchant} do
      {:ok, merchant} = Merchants.update_merchant(merchant, %{enabled: false})

      assert {:error, :merchant_disabled} = Ingestion.ingest(attrs(merchant), new_key())
      assert_nothing_stored()
    end
  end

  describe "Requirement: Payload size limit" do
    test "Scenario: Payload too large", %{merchant: merchant} do
      payload = %{"data" => String.duplicate("a", 300 * 1024)}

      assert {:error, :payload_too_large} =
               Ingestion.ingest(attrs(merchant, %{"payload" => payload}), new_key())

      assert_nothing_stored()
    end
  end

  describe "Requirement: One delivery per interested endpoint" do
    test "Scenario: Matching and filtered endpoints", %{merchant: merchant} do
      {payments, _} = endpoint_fixture(%{merchant_id: merchant.id, event_types: ["payment.*"]})
      {refunds, _} = endpoint_fixture(%{merchant_id: merchant.id, event_types: ["refund.*"]})
      {disabled, _} = endpoint_fixture(%{merchant_id: merchant.id})
      {:ok, _} = Endpoints.update_endpoint(disabled, %{enabled: false})

      assert {:ok, :created, event} = Ingestion.ingest(attrs(merchant), new_key())

      by_endpoint = Map.new(event.deliveries, &{&1.endpoint_id, &1})
      assert map_size(by_endpoint) == 2
      refute Map.has_key?(by_endpoint, disabled.id)

      assert %Delivery{status: "pending", completed_at: nil} = by_endpoint[payments.id]

      assert %Delivery{status: "skipped", window_ends_at: nil, completed_at: completed_at} =
               by_endpoint[refunds.id]

      assert completed_at == event.received_at
      assert count(Delivery) == 2
    end

    test "Scenario: Retry window recorded", %{merchant: merchant} do
      {endpoint, _} = endpoint_fixture(%{merchant_id: merchant.id, retry_window_seconds: 3600})

      assert {:ok, :created, event} = Ingestion.ingest(attrs(merchant), new_key())
      assert [delivery] = event.deliveries
      assert delivery.endpoint_id == endpoint.id
      assert delivery.status == "pending"
      assert DateTime.diff(delivery.window_ends_at, event.received_at, :second) == 3600

      stored = Repo.get!(Delivery, delivery.id)
      assert stored.window_ends_at == delivery.window_ends_at
    end

    test "Scenario: Merchant without endpoints", %{merchant: merchant} do
      assert {:ok, :created, event} = Ingestion.ingest(attrs(merchant), new_key())
      assert event.deliveries == []
      assert count(Event) == 1
      assert count(Delivery) == 0
    end
  end

  describe "Requirement: Events are stored atomically" do
    test "Scenario: Failure while storing deliveries", %{merchant: merchant} do
      endpoint_fixture(%{merchant_id: merchant.id})
      endpoint_fixture(%{merchant_id: merchant.id})

      assert {:ok, multi} = Ingestion.ingest_multi(attrs(merchant), new_key())

      result =
        multi
        |> Ecto.Multi.run(:fail, fn _repo, _changes -> {:error, :storage_failed} end)
        |> Repo.transact()

      assert {:error, :fail, :storage_failed, %{event: %Event{}, deliveries: [_, _]}} = result
      assert_nothing_stored()
    end
  end
end
