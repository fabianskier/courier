defmodule Courier.Delivery.DeliverySchemaTest do
  use Courier.DataCase, async: true

  import Courier.EndpointsFixtures
  import Courier.EventsFixtures

  alias Courier.Delivery.Delivery

  defp insert_delivery(attrs) do
    %Delivery{}
    |> Delivery.create_changeset(attrs)
    |> Repo.insert()
  end

  setup do
    {endpoint, _secret} = endpoint_fixture()
    event = event_fixture(%{merchant_id: endpoint.merchant_id})
    %{endpoint: endpoint, event: event}
  end

  describe "Requirement: One delivery per interested endpoint" do
    test "a second original delivery for the same event and endpoint violates the unique index",
         %{endpoint: endpoint, event: event} do
      attrs = %{
        event_id: event.id,
        endpoint_id: endpoint.id,
        status: "pending",
        window_ends_at: DateTime.add(event.received_at, endpoint.retry_window_seconds)
      }

      assert {:ok, original} = insert_delivery(attrs)
      assert original.attempt_count == 0
      assert original.triggered_by == "system"

      assert {:error, changeset} = insert_delivery(%{attrs | status: "skipped"})
      assert %{event_id: ["has already been taken"]} = errors_on(changeset)

      assert Repo.aggregate(Delivery, :count) == 1

      # A resend is a new delivery for the same pair and is allowed.
      assert {:ok, _resend} =
               insert_delivery(
                 Map.merge(attrs, %{resend_of_id: original.id, triggered_by: "operator"})
               )

      assert Repo.aggregate(Delivery, :count) == 2
    end

    test "the database rejects an unknown status", %{endpoint: endpoint, event: event} do
      changeset =
        %Delivery{}
        |> Ecto.Changeset.change(event_id: event.id, endpoint_id: endpoint.id, status: "lost")

      assert {:error, changeset} =
               changeset
               |> Ecto.Changeset.check_constraint(:status, name: :status_values)
               |> Repo.insert()

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end
end
