defmodule Courier.Telemetry.IngestionTelemetryTest do
  # Not async: telemetry handlers are global, so events of other tests would arrive here.
  use Courier.DataCase, async: false

  import Courier.EndpointsFixtures
  import Courier.MerchantsFixtures

  alias Courier.Ingestion

  setup do
    test_pid = self()
    handler_id = "ingestion-telemetry-#{inspect(test_pid)}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        Courier.Telemetry.events(),
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    merchant = merchant_fixture()
    endpoint_fixture(%{merchant_id: merchant.id, event_types: ["payment.*"]})
    endpoint_fixture(%{merchant_id: merchant.id, event_types: ["refund.*"]})

    attrs = %{
      "type" => "payment.succeeded",
      "merchant_id" => merchant.id,
      "payload" => %{"amount" => 1000, "currency" => "EUR"}
    }

    %{merchant: merchant, attrs: attrs, key: "key-#{System.unique_integer([:positive])}"}
  end

  describe "Requirement: Ingestion telemetry" do
    test "Scenario: New event emits ingested", %{merchant: merchant, attrs: attrs, key: key} do
      assert {:ok, :created, _event} = Ingestion.ingest(attrs, key)

      assert_received {:telemetry, [:courier, :event, :ingested], measurements, metadata}
      assert measurements == %{deliveries: 2, pending: 1}
      assert metadata == %{merchant_id: merchant.id, type: "payment.succeeded"}

      refute_received {:telemetry, _, _, _}
    end

    test "Scenario: Repeat emits nothing", %{attrs: attrs, key: key} do
      assert {:ok, :created, _event} = Ingestion.ingest(attrs, key)
      assert_received {:telemetry, [:courier, :event, :ingested], _, _}

      assert {:ok, :repeat, _event} = Ingestion.ingest(attrs, key)
      refute_received {:telemetry, _, _, _}
    end

    test "a rejected event emits nothing", %{attrs: attrs, key: key} do
      assert {:ok, :created, _event} = Ingestion.ingest(attrs, key)
      assert_received {:telemetry, [:courier, :event, :ingested], _, _}

      assert {:error, :idempotency_key_reused} =
               Ingestion.ingest(%{attrs | "type" => "payment.failed"}, key)

      assert {:error, %Ecto.Changeset{}} = Ingestion.ingest(Map.delete(attrs, "type"), "other")
      refute_received {:telemetry, _, _, _}
    end
  end
end
