defmodule CourierDemo.Receiver.Secrets do
  @moduledoc """
  In-memory signing keys of the demo receiver, by endpoint name.

  Secrets arrive through `PUT /_secrets/:name` and are never written to disk
  or logged; they are lost when the receiver stops.
  """

  use Agent

  @prefix "whsec_"

  @doc """
  Starts the agent. `:name` defaults to this module.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Stores the key of a `whsec_<base64>` secret under `name`, replacing any
  earlier one. Returns `:error`, changing nothing, when the secret is not in
  that form.
  """
  @spec put(Agent.agent(), String.t(), term()) :: :ok | :error
  def put(agent, name, @prefix <> encoded) when encoded != "" do
    case Base.decode64(encoded) do
      {:ok, key} -> Agent.update(agent, &Map.put(&1, name, key))
      :error -> :error
    end
  end

  def put(_agent, _name, _secret), do: :error

  @doc """
  Returns the decoded signing key registered for `name`, or `nil`.
  """
  @spec key(Agent.agent(), String.t()) :: binary() | nil
  def key(agent, name), do: Agent.get(agent, &Map.get(&1, name))
end
