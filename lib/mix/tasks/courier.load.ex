defmodule Mix.Tasks.Courier.Load do
  @shortdoc "Measures ingestion latency and delivery timing under load"

  @moduledoc """
  Sends distinct events to `POST <url>/api/v1/events` at a steady rate, waits
  for their deliveries' first attempts and prints the ingestion and delivery
  report (`CourierDemo.Load`).

      $ mix courier.load --merchant ID [--merchant ID...] [options]

  ## Options

    * `--merchant ID` - merchant to send events for (required, repeatable)
    * `--token TOKEN` - API key with the `ingest` scope (default: the
      `COURIER_INGEST_TOKEN` environment variable; required)
    * `--url URL` - courier's base URL (default `http://localhost:4000`)
    * `--rate N` - events per second (default `50`)
    * `--count N` - number of events (default `500`)
    * `--wait N` - seconds to wait for first attempts (default `30`)

  Only `Courier.Repo` is started, to read the delivery timings; the rest of
  the application is not. Missing or invalid options print what is wrong and
  exit with status 1 without sending anything. The token is never printed.

  ## Example

      $ COURIER_INGEST_TOKEN=ck_... mix courier.load \\
          --merchant 0d0c6e0a-6f0e-4f0e-9d51-6f0c1a2b3c4d --rate 50 --count 1500
  """

  use Mix.Task

  alias CourierDemo.{CLI, Load}

  @impl Mix.Task
  def run(args) do
    case Load.parse(args) do
      {:ok, config} ->
        # Compiles and loads the configuration without starting the application.
        Mix.Task.run("app.config")
        config |> CLI.run_load() |> Enum.each(&Mix.shell().info(&1))

      {:error, errors} ->
        Enum.each(errors, &Mix.shell().error(&1))
        Mix.shell().error("Usage: mix courier.load --merchant ID [--merchant ID...] [options]")
        exit({:shutdown, 1})
    end
  end
end
