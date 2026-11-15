defmodule CourierWeb.LogCapture do
  @moduledoc """
  Captures debug-level logs in tests.

  Ecto logs queries at `:debug`, but the primary log level in test is higher
  and is checked before any process level. `capture_debug_log/1` lowers the
  primary level to `:debug` only while the given function runs and restores
  it afterwards. The primary level is global, so tests that use this helper
  must be `async: false`.
  """

  @doc """
  Runs `fun` with debug logging enabled and returns `{result, log}`.
  """
  @spec capture_debug_log((-> result)) :: {result, String.t()} when result: term()
  def capture_debug_log(fun) when is_function(fun, 0) do
    previous = Logger.level()
    Logger.configure(level: :debug)

    try do
      ExUnit.CaptureLog.with_log([level: :debug], fun)
    after
      Logger.configure(level: previous)
    end
  end
end
