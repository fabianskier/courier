defmodule CourierMCP.Call do
  @moduledoc """
  Runs a tool call: turns its result into an MCP tool response and writes the
  call log. Every tool's `execute/2` goes through `run/4`, so no call can
  skip the log.

  The log line has the tool, the name of the API key, the result status, the
  duration and the tool's declared arguments. It never has the token, a
  payload or a response body.
  """

  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias Courier.Access.ApiKey

  require Logger

  @type result :: {:ok, map()} | {:error, code :: String.t(), message :: String.t()}

  @doc """
  Runs `fun` for `tool` and replies on `frame`.

  `{:ok, map}` becomes a JSON tool response; `{:error, code, message}` becomes
  a tool error (`isError`) with the body `{"error": {"code", "message"}}`.
  """
  @spec run(String.t(), Frame.t(), map(), (-> result())) :: {:reply, Response.t(), Frame.t()}
  def run(tool, %Frame{} = frame, args, fun) when is_map(args) and is_function(fun, 0) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    duration = System.monotonic_time(:millisecond) - started

    Logger.info(fn ->
      "mcp tool=#{tool} key=#{key_name(frame)} status=#{status(result)} " <>
        "duration_ms=#{duration} args=#{Jason.encode!(args)}"
    end)

    {:reply, response(result), frame}
  end

  defp response({:ok, data}) when is_map(data), do: Response.json(Response.tool(), data)

  defp response({:error, code, message}) do
    Response.tool()
    |> Response.json(%{error: %{code: code, message: message}})
    |> Map.put(:isError, true)
  end

  defp status({:ok, _data}), do: "ok"
  defp status({:error, code, _message}), do: "error:#{code}"

  defp key_name(%Frame{assigns: %{current_key: %ApiKey{name: name}}}), do: name
  defp key_name(_frame), do: "unknown"
end
