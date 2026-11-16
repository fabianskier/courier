defmodule CourierWeb.Router do
  use CourierWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug CourierWeb.Plugs.Authenticate
  end

  pipeline :admin do
    plug :fetch_session
    plug :protect_from_forgery
    plug CourierWeb.Plugs.AdminAuth
  end

  scope "/api", CourierWeb do
    pipe_through :api
  end

  scope "/api/v1", CourierWeb do
    pipe_through [:api, :authenticated]

    get "/me", MeController, :show

    resources "/merchants", MerchantController, only: [:index, :show, :create, :update]
    resources "/endpoints", EndpointController, only: [:index, :show, :create, :update]
    post "/endpoints/:id/rotate_secret", EndpointController, :rotate_secret

    resources "/events", EventController, only: [:index, :show, :create]
    resources "/deliveries", DeliveryController, only: [:show]
    post "/deliveries/:id/resend", DeliveryController, :resend
  end

  # LiveDashboard for operators, in every environment, behind the admin token.
  scope "/admin" do
    pipe_through :admin

    live_dashboard "/dashboard",
      metrics: CourierWeb.Telemetry,
      ecto_repos: [Courier.Repo]
  end
end
