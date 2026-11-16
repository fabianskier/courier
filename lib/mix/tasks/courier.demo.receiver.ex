defmodule Mix.Tasks.Courier.Demo.Receiver do
  @shortdoc "Runs the demo webhook receiver"

  @moduledoc """
  Runs the demo webhook receiver (`CourierDemo.Receiver`) until stopped.

      $ mix courier.demo.receiver [--port PORT] [--ip ADDRESS]

  It listens on `127.0.0.1:4001` by default. The courier application is not
  started, so no database is needed. `COURIER_DEMO_TIMEOUT_MS` sets how long
  `/hooks/<name>/timeout` waits before answering (default `35000`).

  Invalid options print the usage and exit with status 1.

  ## Example

      $ COURIER_DEMO_TIMEOUT_MS=5000 mix courier.demo.receiver --port 4010
  """

  use Mix.Task

  @switches [port: :integer, ip: :string]

  @impl Mix.Task
  def run(args) do
    with {opts, [], []} <- OptionParser.parse(args, strict: @switches),
         {:ok, opts} <- parse_ip(opts),
         true <- Keyword.get(opts, :port, 4001) in 0..65_535 do
      # Compiles and loads the configuration without starting the application.
      Mix.Task.run("app.config")
      CourierDemo.Receiver.serve(opts)
    else
      _invalid ->
        Mix.shell().error("Usage: mix courier.demo.receiver [--port PORT] [--ip ADDRESS]")
        exit({:shutdown, 1})
    end
  end

  defp parse_ip(opts) do
    case Keyword.fetch(opts, :ip) do
      {:ok, ip} ->
        with {:ok, address} <- :inet.parse_address(String.to_charlist(ip)) do
          {:ok, Keyword.put(opts, :ip, address)}
        end

      :error ->
        {:ok, opts}
    end
  end
end
