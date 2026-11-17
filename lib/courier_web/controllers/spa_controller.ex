defmodule CourierWeb.SpaController do
  @moduledoc """
  Serves the dashboard SPA (`frontend/`, built by Vite into `priv/static`).

  Every GET path the router does not match otherwise answers with
  `index.html`, so client routes such as `/deliveries/123` survive a reload;
  the SPA's router shows its own not-found page. Paths under the server's own
  prefixes (`/api`, `/admin`, `/dev`, `/socket`) keep the usual 404; `/mcp` has its
  own forward.

  Hashed assets (`/assets/...`) are served by `Plug.Static` before the router.
  """

  use CourierWeb, :controller

  @server_prefixes ~w(api admin dev socket)

  def index(%Plug.Conn{path_info: [prefix | _]} = conn, _params)
      when prefix in @server_prefixes do
    raise Phoenix.Router.NoRouteError, conn: conn, router: CourierWeb.Router
  end

  def index(conn, _params) do
    path = index_path()

    if File.regular?(path) do
      conn
      |> put_resp_content_type("text/html")
      # The page names the hashed assets of the current build: never cache it.
      |> put_resp_header("cache-control", "no-cache")
      |> send_file(200, path)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(
        :not_found,
        "The dashboard is not built. Run `npm run build` in frontend/, " <>
          "or use the Vite dev server (`npm run dev`, http://localhost:5173).\n"
      )
    end
  end

  # Configurable so tests can point at a fixture instead of a real build.
  defp index_path do
    Application.get_env(:courier, __MODULE__, [])
    |> Keyword.get_lazy(:index_path, fn ->
      Application.app_dir(:courier, "priv/static/index.html")
    end)
  end
end
