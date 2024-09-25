defmodule Chatgpt.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    verify_oauth_config()

    children = [
      # Start the Telemetry supervisor
      ChatgptWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Chatgpt.PubSub},
      # Start Finch
      {Finch, name: Chatgpt.Finch},
      # Start your ETS Session Manager before the Endpoint
      Chatgpt.Ets.SessionIdManager,
      # Start the Endpoint (http/https)
      ChatgptWeb.Endpoint,
      # Start a worker by calling: Chatgpt.Worker.start_link(arg)
      # {Chatgpt.Worker, arg},
      Chatgpt.Tokenizer
      # TODO: only needed if using vertex?
      # {Goth, name: Chatgpt.Goth}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chatgpt.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp verify_oauth_config do
    required_configs = [
      :client_id,
      :client_secret,
      :redirect_uri
    ]

    Enum.each(required_configs, fn config ->
      unless Application.get_env(:elixir_auth_google, config) do
        raise "Missing required configuration: :elixir_auth_google, :#{config}"
      end
    end)

    unless Application.get_env(:elixir_auth_google, :scopes) do
      Logger.warning("No scopes configured for :elixir_auth_google. Using default scopes.")
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChatgptWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
