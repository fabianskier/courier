defmodule Mix.Courier do
  @moduledoc false

  @doc """
  Starts the application for a `mix courier.*` task with the current
  process's log level raised to at least `:info`, so Ecto's debug SQL lines
  are not printed. A stricter global level is kept, and other processes are
  not affected.
  """
  def start_app do
    Logger.put_process_level(self(), quiet_level(Logger.level()))
    Mix.Task.run("app.start")
  end

  defp quiet_level(level) do
    if Logger.compare_levels(level, :info) == :lt, do: :info, else: level
  end
end
