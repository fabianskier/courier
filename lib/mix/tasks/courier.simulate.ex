defmodule Mix.Tasks.Courier.Simulate do
  @shortdoc "Sends demo events to courier's ingestion API"

  @moduledoc """
  Sends events to `POST <url>/api/v1/events` at a steady rate, with a share of
  exact repeats (`CourierDemo.Simulator`), and prints a summary.

      $ mix courier.simulate --merchant ID [--merchant ID...] [options]

  ## Options

    * `--merchant ID` - merchant to send events for (required, repeatable)
    * `--token TOKEN` - API key with the `ingest` scope (default: the
      `COURIER_INGEST_TOKEN` environment variable; required)
    * `--url URL` - courier's base URL (default `http://localhost:4000`)
    * `--count N` - number of requests (default `100`, at least 1)
    * `--rate N` - requests per second (default `5`, 1 to 1000)
    * `--repeat-share S` - share of requests that repeat an earlier one with
      the same idempotency key and body (default `0.1`, from 0 to 1)
    * `--types A,B` - event types (default
      `payment.succeeded,payment.failed,refund.succeeded`)

  The courier application is not started: the task talks to the API like any
  producer. Missing or invalid options print what is wrong and exit with
  status 1 without sending anything. The token is never printed.

  ## Example

      $ COURIER_INGEST_TOKEN=ck_... mix courier.simulate \\
          --merchant 0d0c6e0a-6f0e-4f0e-9d51-6f0c1a2b3c4d --count 50 --rate 10
  """

  use Mix.Task

  alias CourierDemo.CLI

  @impl Mix.Task
  def run(args) do
    case CLI.parse_simulate(args) do
      {:ok, config} ->
        simulate(config)

      {:error, errors} ->
        Enum.each(errors, &Mix.shell().error(&1))

        Mix.shell().error(
          "Usage: mix courier.simulate --merchant ID [--merchant ID...] [options]"
        )

        exit({:shutdown, 1})
    end
  end

  defp simulate(config) do
    # Compiles and loads the configuration without starting the application.
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:req)

    config |> CLI.run_simulation() |> CLI.summary() |> Enum.each(&Mix.shell().info(&1))
  end
end
