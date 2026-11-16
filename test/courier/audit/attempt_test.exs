defmodule Courier.Audit.AttemptTest do
  use Courier.DataCase, async: true

  import Courier.AuditFixtures

  alias Courier.Audit
  alias Courier.Audit.Attempt

  describe "Requirement: Attempts are append-only" do
    test "Scenario: Update rejected" do
      attempt = attempt_fixture(%{response_status: 500})

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        attempt |> Ecto.Changeset.change(response_status: 200) |> Repo.update!()
      end

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Attempt |> where(id: ^attempt.id) |> Repo.update_all(set: [error: "changed"])
      end

      stored = Repo.get!(Attempt, attempt.id)
      assert stored.response_status == 500
      assert stored.error == nil
    end

    test "Scenario: Delete rejected outside retention" do
      attempt = attempt_fixture()

      assert_raise Postgrex.Error, ~r/append-only/, fn -> Repo.delete!(attempt) end

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.transact(fn ->
          Repo.query!("SET LOCAL courier.retention = off")
          {:ok, Repo.delete_all(where(Attempt, id: ^attempt.id))}
        end)
      end

      assert Repo.get(Attempt, attempt.id)
    end

    test "Scenario: Delete allowed for retention" do
      attempt = attempt_fixture()

      assert {:ok, {1, _}} =
               Repo.transact(fn ->
                 Repo.query!("SET LOCAL courier.retention = on")
                 {:ok, Repo.delete_all(where(Attempt, id: ^attempt.id))}
               end)

      refute Repo.get(Attempt, attempt.id)
    end
  end

  describe "attempt numbering" do
    test "the same number twice for one delivery violates the unique index" do
      attempt = attempt_fixture()

      assert {:error, changeset} =
               %Attempt{}
               |> Attempt.create_changeset(%{
                 delivery_id: attempt.delivery_id,
                 number: 1,
                 started_at: DateTime.utc_now(),
                 duration_ms: 10,
                 url: attempt.url
               })
               |> Repo.insert()

      assert %{delivery_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "the same number for different deliveries is allowed" do
      attempt_fixture(%{number: 1})
      assert %Attempt{number: 1} = attempt_fixture(%{number: 1})
    end
  end

  describe "list_attempts/1" do
    test "returns only the delivery's attempts ordered by number" do
      delivery = delivery_fixture()

      for number <- [3, 1, 2] do
        attempt_fixture(%{delivery_id: delivery.id, number: number})
      end

      attempt_fixture()

      attempts = Audit.list_attempts(delivery.id)

      assert Enum.map(attempts, & &1.number) == [1, 2, 3]
      assert Enum.all?(attempts, &(&1.delivery_id == delivery.id))
    end

    test "returns an empty list for a delivery without attempts" do
      assert Audit.list_attempts(delivery_fixture().id) == []
    end
  end
end
