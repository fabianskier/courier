defmodule CourierMCP.Client do
  @moduledoc """
  A small MCP client for tests: JSON-RPC over HTTP against `/mcp` through
  `Phoenix.ConnTest`, so scenarios cover routing, authentication and the MCP
  library together.

  `request/4` returns the raw conn (for status codes); `connect/1`,
  `list_tools/2` and `call_tool/4` return decoded results. The token is given
  on every call, so a test can reuse a session with another key.
  """

  import Plug.Conn

  @path "/mcp"
  @session_header "mcp-session-id"
  @protocol_version "2025-06-18"

  @doc "Sends one JSON-RPC message and returns the conn. `token` and `session_id` may be nil."
  def request(token, session_id, method, params \\ nil) do
    message = %{jsonrpc: "2.0", method: method}
    message = if params, do: Map.put(message, :params, params), else: message

    message =
      if String.starts_with?(method, "notifications/"),
        do: message,
        else: Map.put(message, :id, System.unique_integer([:positive]))

    Phoenix.ConnTest.build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> put_header("authorization", token && "Bearer " <> token)
    |> put_header(@session_header, session_id)
    |> put_header("mcp-protocol-version", session_id && @protocol_version)
    |> Phoenix.ConnTest.dispatch(CourierWeb.Endpoint, :post, @path, Jason.encode!(message))
  end

  @doc "Sends `initialize` and returns the conn."
  def initialize(token) do
    request(token, nil, "initialize", %{
      protocolVersion: @protocol_version,
      capabilities: %{},
      clientInfo: %{name: "courier-test", version: "1.0.0"}
    })
  end

  @doc "Completes the handshake and returns `%{id: session_id, result: initialize_result}`."
  def connect(token) do
    conn = initialize(token)
    %{"result" => result} = Phoenix.ConnTest.json_response(conn, 200)
    [session_id] = get_resp_header(conn, @session_header)

    %Plug.Conn{status: 202} = request(token, session_id, "notifications/initialized")

    %{id: session_id, result: result}
  end

  @doc "Returns the list of tools of the session."
  def list_tools(token, session) do
    %{"result" => %{"tools" => tools}} = rpc(token, session, "tools/list")
    tools
  end

  @doc """
  Calls a tool. Returns `{:ok, data}` or `{:error, data}` (a tool error) with
  the decoded JSON of the result, or `{:rpc_error, error}` when the call was
  rejected before the tool ran.
  """
  def call_tool(token, session, name, arguments) do
    case rpc(token, session, "tools/call", %{name: name, arguments: arguments}) do
      %{"result" => %{"content" => [%{"type" => "text", "text" => text}]} = result} ->
        status = if result["isError"], do: :error, else: :ok
        {status, Jason.decode!(text)}

      %{"error" => error} ->
        {:rpc_error, error}
    end
  end

  defp rpc(token, session, method, params \\ nil) do
    token |> request(session.id, method, params) |> Map.fetch!(:resp_body) |> Jason.decode!()
  end

  defp put_header(conn, _name, nil), do: conn
  defp put_header(conn, name, value), do: put_req_header(conn, name, value)
end
