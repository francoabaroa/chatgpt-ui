defmodule ChatgptWeb.Router do
  use ChatgptWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ChatgptWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_view, html: ChatgptWeb.PageHTML
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_authenticated_user do
    plug :ensure_authenticated_user
  end

  scope "/", ChatgptWeb do
    pipe_through :browser

    get "/auth/google", AuthController, :oauth
    get "/auth/google/callback", AuthController, :oauth_callback

    scope "/" do
      pipe_through :require_authenticated_user

      get "/", PageController, :chat
      get "/chat", PageController, :chat
      get "/assistant/:scenario_id", PageController, :scenario
      get "/list-drive-files", PageController, :list_drive_files
      get "/drive_files", PageController, :drive_files
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ChatgptWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:chatgpt, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ChatgptWeb.Telemetry
    end
  end

  defp ensure_authenticated_user(conn, _opts) do
    if get_session(conn, "access_token") do
      conn
    else
      conn
      |> redirect(to: "/auth/google")
      |> halt()
    end
  end
end
