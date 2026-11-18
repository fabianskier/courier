defmodule CourierWeb.ChannelCase do
  @moduledoc """
  The test case for tests that require channels.

  It imports `Phoenix.ChannelTest` and sets up the SQL sandbox, as
  `Courier.DataCase` does, so channel processes can use the database.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import CourierWeb.ChannelCase

      # The default endpoint for testing
      @endpoint CourierWeb.Endpoint
    end
  end

  setup tags do
    Courier.DataCase.setup_sandbox(tags)
    :ok
  end
end
