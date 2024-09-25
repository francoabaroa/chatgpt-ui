defmodule ChatgptWeb.PageController do
  use ChatgptWeb, :controller

  defp protect_with_session(conn, _params, fx) do
    access_token = get_session(conn, "access_token")
    oauth_expiration = get_session(conn, "oauth_expiration")

    cond do
      is_nil(access_token) or is_nil(oauth_expiration) ->
        scopes = Application.get_env(:elixir_auth_google, :scopes)
        oauth_google_url = ElixirAuthGoogle.generate_oauth_url(conn)
        redirect(conn, external: oauth_google_url)

      DateTime.compare(DateTime.utc_now(), oauth_expiration) == :gt ->
        scopes = Application.get_env(:elixir_auth_google, :scopes)
        oauth_google_url = ElixirAuthGoogle.generate_oauth_url(conn)
        redirect(conn, external: oauth_google_url)

      true ->
        fx.()
    end
  end

  defp render_page(conn, params, args) do
    default_model = Application.get_env(:chatgpt, :default_model, :"gpt-3.5-turbo")

    # get model from session, or overwrite with model from params
    session_model =
      case get_session(conn) do
        %{"model" => model} ->
          model

        _ ->
          default_model
      end

    model =
      case Map.get(params, "model", nil) do
        nil -> session_model
        m -> m
      end

    args =
      Map.merge(
        %{
          "model" => model,
          "models" => Application.get_env(:chatgpt, :models, [model]),
          "scenarios" => ChatgptWeb.Scenario.default_scenarios()
        },
        args
      )

    conn = put_session(conn, "model", Map.get(params, "model", model))

    if Application.get_env(:chatgpt, :enable_google_oauth, false) do
      protect_with_session(
        conn,
        params,
        fn ->
          live_render(conn, ChatgptWeb.IndexLive, session: args)
        end
      )
    else
      live_render(conn, ChatgptWeb.IndexLive, session: args)
    end
  end

  def chat(conn, params) do
    render_page(conn, params, %{"mode" => :chat})
  end

  def scenario(conn, params) do
    scenario =
      ChatgptWeb.Scenario.default_scenarios()
      |> Enum.find(fn sc -> sc.id == Map.get(params, "scenario_id", nil) end)

    render_page(conn, params, %{} |> Map.put("mode", :scenario) |> Map.put("scenario", scenario))
  end

  def drive_files(conn, _params) do
    protect_with_session(conn, _params, fn ->
      access_token = get_session(conn, "access_token")

      case Chatgpt.Drive.list_files(access_token) do
        {:ok, files} ->
          render(conn, :drive_files, files: files)

        {:error, reason} ->
          conn
          |> put_flash(:error, "Failed to fetch Drive files: #{inspect(reason)}")
          |> redirect(to: "/")
      end
    end)
  end
end
