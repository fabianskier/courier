defmodule CourierWeb.DashboardChannel do
  @moduledoc """
  Forwards change notices (`Courier.Notices`) to dashboard clients.

  Topics are `dashboard:events`, `dashboard:deliveries`, `dashboard:endpoints`
  and `dashboard:merchants`; any other topic is refused. Each joined channel
  re-checks its API key periodically (every 30 seconds by default, see
  `:key_check_interval`) and stops once the key is revoked or has lost the
  `read` scope, which closes it for the client.
  """

  use Phoenix.Channel

  alias Courier.Access
  alias Courier.Notices

  @resources %{
    "events" => :events,
    "deliveries" => :deliveries,
    "endpoints" => :endpoints,
    "merchants" => :merchants
  }

  @default_key_check_interval :timer.seconds(30)

  @impl true
  def join("dashboard:" <> resource, _payload, socket) do
    case Map.fetch(@resources, resource) do
      {:ok, resource} ->
        :ok = Phoenix.PubSub.subscribe(Courier.PubSub, Notices.topic(resource))
        schedule_key_check()
        {:ok, socket}

      :error ->
        {:error, %{reason: "unknown topic"}}
    end
  end

  @impl true
  def handle_info({:notice, name, payload}, socket) do
    push(socket, name, payload)
    {:noreply, socket}
  end

  def handle_info(:check_key, socket) do
    with {:ok, key} <- Access.reload_active_key(socket.assigns.api_key_id),
         true <- Access.has_scope?(key, :read) do
      schedule_key_check()
      {:noreply, socket}
    else
      _ -> {:stop, :normal, socket}
    end
  end

  defp schedule_key_check do
    Process.send_after(self(), :check_key, key_check_interval())
  end

  defp key_check_interval do
    :courier
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:key_check_interval, @default_key_check_interval)
  end
end
