defmodule Courier.Delivery.Client do
  @moduledoc """
  Sends one webhook request and reduces the outcome to what an attempt
  stores.

  Requests never retry and never follow redirects (the worker owns both
  decisions), and do not decode the response body. They use the
  `Courier.Finch` pool, which sets the connect timeout; the receive timeout
  is set per request.

  The response body is streamed and reading stops after its first
  4096 bytes, which closes the connection. Each request runs in a task
  under `Courier.Delivery.TaskSupervisor` and is killed when it has not
  finished within a total deadline (30 s by default, from connect to the end
  of reading), so a body that trickles in cannot keep a job busy.

  Req options come from, in increasing precedence: the defaults here,
  `config :courier, Courier.Delivery.Client` (tests set
  `plug: {Req.Test, Courier.Delivery.Client}`) and the `opts` given to
  `post/4`. In `opts`, `:deadline` sets the total deadline in milliseconds and
  `plug: nil` removes any configured plug, so the request reaches a real
  server through Finch.
  """

  @receive_timeout 15_000
  @deadline 30_000
  @max_body_bytes 4096
  @max_error_bytes 255

  @type response :: %{
          status: integer(),
          retry_after: String.t() | nil,
          body: String.t()
        }

  @doc """
  POSTs `body` with `headers` to `url`.

  Returns `{:ok, %{status, retry_after, body}}` for any HTTP response, where
  `retry_after` is the raw `Retry-After` header (or `nil`) and `body` holds at
  most the first #{@max_body_bytes} bytes with invalid UTF-8 and NUL bytes
  replaced, or `{:error, reason}` with a short reason such as `"timeout"`.

  `opts` override the defaults and the application config; see the module
  documentation for `:deadline` and `plug: nil`.
  """
  @spec post(String.t(), iodata(), [{String.t(), String.t()}], keyword()) ::
          {:ok, response()} | {:error, String.t()}
  def post(url, body, headers, opts \\ []) do
    {deadline, opts} = Keyword.pop(opts, :deadline, @deadline)

    options =
      [
        url: url,
        body: body,
        headers: headers,
        retry: false,
        redirect: false,
        decode_body: false,
        receive_timeout: @receive_timeout,
        finch: [name: Courier.Finch],
        into: &collect_limited/2
      ]
      |> Keyword.merge(Application.get_env(:courier, __MODULE__, []))
      |> Keyword.merge(opts)
      |> drop_nil_plug()

    case run_with_deadline(options, deadline) do
      {:ok, %Req.Response{} = response} ->
        {:ok,
         %{
           status: response.status,
           retry_after: response |> Req.Response.get_header("retry-after") |> List.first(),
           body: sanitize_body(response.body)
         }}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, exception} ->
        {:error, error_reason(exception)}
    end
  end

  @doc """
  Keeps the first #{@max_body_bytes} bytes of `body` and makes the result
  valid UTF-8 without NUL bytes, so it fits a PostgreSQL `text` column.
  """
  @spec sanitize_body(term()) :: String.t()
  def sanitize_body(body) when is_binary(body) do
    body
    |> binary_part(0, min(byte_size(body), @max_body_bytes))
    |> clean_text()
  end

  def sanitize_body(nil), do: ""
  def sanitize_body(body), do: body |> IO.iodata_to_binary() |> sanitize_body()

  defp drop_nil_plug(options) do
    case Keyword.fetch(options, :plug) do
      {:ok, nil} -> Keyword.delete(options, :plug)
      _ -> options
    end
  end

  defp run_with_deadline(options, deadline) do
    task =
      Task.Supervisor.async_nolink(Courier.Delivery.TaskSupervisor, fn -> Req.post(options) end)

    case Task.yield(task, deadline) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
      nil -> {:error, "timeout"}
    end
  end

  # Appends each chunk to the body up to @max_body_bytes, then stops reading.
  defp collect_limited({:data, chunk}, {request, response}) do
    room = @max_body_bytes - byte_size(response.body)
    body = response.body <> binary_part(chunk, 0, min(byte_size(chunk), room))
    response = %{response | body: body}

    if byte_size(body) >= @max_body_bytes do
      {:halt, {request, response}}
    else
      {:cont, {request, response}}
    end
  end

  defp error_reason(%Req.TransportError{reason: reason}) when is_atom(reason),
    do: Atom.to_string(reason)

  defp error_reason(exception) when is_exception(exception) do
    exception
    |> Exception.message()
    |> clean_text()
    |> String.slice(0, @max_error_bytes)
  end

  defp error_reason(other), do: other |> inspect() |> String.slice(0, @max_error_bytes)

  defp clean_text(binary) do
    binary
    |> String.replace_invalid()
    |> String.replace(<<0>>, "�")
  end
end
