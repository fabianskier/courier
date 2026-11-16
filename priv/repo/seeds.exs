# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Courier.Repo.insert!(%Courier.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Demo data for the demo receiver (see "Demo tools" in docs/architecture.md).
# It refuses to run twice on the same database.
[] |> CourierDemo.Seeds.run() |> CourierDemo.Seeds.report() |> IO.puts()
