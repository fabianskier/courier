defmodule CourierMCP.Server do
  @moduledoc """
  The MCP server of courier: a thin adapter over the contexts, served over
  Streamable HTTP at `/mcp` behind the API's authentication.

  Tools read the API key of the current request from
  `frame.assigns.current_key` and go through `CourierMCP.Call`.
  """

  use Anubis.Server,
    name: "courier",
    version: Mix.Project.config()[:version],
    capabilities: [:tools]

  component(CourierMCP.Tools.GetEvent)
  component(CourierMCP.Tools.GetDelivery)
  component(CourierMCP.Tools.ListDeliveries)
  component(CourierMCP.Tools.ListFailedDeliveries)
  component(CourierMCP.Tools.GetEndpointHealth)
end
