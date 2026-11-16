defmodule Courier.Delivery.IsolationReceiver do
  @moduledoc """
  A merchant endpoint for the isolation test: a plug served by a real Bandit
  server on loopback. For every request it sends `{:receiver_request, name}`
  to the `:notify` process, waits `:delay_ms` (default 0) and answers `200`.

  Also holds the telemetry handler the test uses to learn when an Oban job
  finished, so the test waits for a message instead of polling.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      notify: Keyword.fetch!(opts, :notify),
      delay_ms: Keyword.get(opts, :delay_ms, 0)
    }
  end

  @impl Plug
  def call(conn, %{name: name, notify: notify, delay_ms: delay_ms}) do
    {:ok, _body, conn} = read_body(conn)
    send(notify, {:receiver_request, name})
    if delay_ms > 0, do: Process.sleep(delay_ms)
    send_resp(conn, 200, "ok")
  end

  @doc """
  Telemetry handler for `[:oban, :job, :stop]`: sends
  `{:job_stop, delivery_id, state}` to the pid given as handler config.
  """
  def handle_job_stop(_event, _measurements, %{job: job, state: state}, pid) do
    send(pid, {:job_stop, job.args["delivery_id"], state})
  end
end
