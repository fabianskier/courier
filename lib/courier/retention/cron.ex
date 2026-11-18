defmodule Courier.Retention.Cron do
  @moduledoc """
  An `Oban.Cron` plugin for the daily retention job.

  Oban accepts each plugin module once, and the `Oban.Plugins.Cron` entry in
  `config/config.exs` keeps its crontab to the `WindowSweeper`. This module
  delegates to `Oban.Cron`, so it runs a second crontab under its own name
  with the same leadership and scheduling behaviour:

      {Courier.Retention.Cron, crontab: [{"30 3 * * *", Courier.Retention.Worker}]}
  """

  @behaviour Oban.Plugin

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @impl Oban.Plugin
  defdelegate start_link(opts), to: Oban.Cron

  @impl Oban.Plugin
  defdelegate validate(opts), to: Oban.Cron

  @doc false
  # Oban checks that a plugin exports init/1; the GenServer is Oban.Cron.
  defdelegate init(state), to: Oban.Cron
end
