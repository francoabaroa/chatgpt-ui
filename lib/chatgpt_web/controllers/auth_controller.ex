defmodule ChatgptWeb.AuthController do
  use ChatgptWeb, :controller
  require Logger

  def oauth(conn, _params) do
    client_id = Application.fetch_env!(:elixir_auth_google, :client_id)
    redirect_uri = Application.fetch_env!(:elixir_auth_google, :redirect_uri)

    scopes =
      Application.get_env(:elixir_auth_google, :scopes)
      |> Enum.join(" ")

    oauth_params = %{
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: scopes,
      access_type: "offline",
      # Forces the consent screen to show every time
      prompt: "consent"
    }

    oauth_url =
      "https://accounts.google.com/o/oauth2/v2/auth?" <>
        URI.encode_query(oauth_params)

    redirect(conn, external: oauth_url)
  end

  def oauth_callback(conn, %{"code" => code}) do
    token_url = "https://oauth2.googleapis.com/token"
    client_id = Application.fetch_env!(:elixir_auth_google, :client_id)
    client_secret = Application.fetch_env!(:elixir_auth_google, :client_secret)
    redirect_uri = Application.fetch_env!(:elixir_auth_google, :redirect_uri)

    token_params = %{
      code: code,
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    }

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    Logger.debug("Token request params: #{inspect(token_params)}")

    case HTTPoison.post(token_url, URI.encode_query(token_params), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        handle_successful_token_response(conn, body)

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("OAuth token request failed with status #{status_code}. Body: #{body}")

        case Jason.decode(body) do
          {:ok, %{"error" => error, "error_description" => description}} ->
            Logger.error("Token error: #{error} - #{description}")
            text(conn, "Authorization failed: #{error} - #{description}")

          {:ok, _} ->
            text(conn, "Authorization failed: Unexpected error")

          _ ->
            text(conn, "Authorization failed: Unable to parse error response")
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        text(conn, "Authorization failed due to a network error. Please try again.")
    end
  end

  defp handle_successful_token_response(conn, body) do
    with {:ok, token_data} <- Jason.decode(body),
         {:ok, access_token} <- fetch_value(token_data, "access_token") do
      case ElixirAuthGoogle.get_user_profile(access_token) do
        {:ok, profile} ->
          case profile[:email] do
            nil ->
              Logger.error("Failed to extract email: email is missing")
              text(conn, "Authorization failed: Unable to extract email from profile")

            email ->
              expires_in = token_data["expires_in"] || 3600
              expiry_datetime = DateTime.add(DateTime.utc_now(), expires_in, :second)

              conn
              |> put_session("access_token", access_token)
              |> put_session("oauth_expiration", expiry_datetime)
              |> put_session("email", email)
              |> configure_session(renew: true)
              |> redirect(to: "/")

            {:error, reason} ->
              Logger.error("Failed to extract email: #{reason}")
              text(conn, "Authorization failed: Unable to extract email from profile")
          end

        {:error, reason} ->
          Logger.error("Failed to fetch user profile: #{reason}")
          text(conn, "Authorization failed: Unable to fetch user profile")
      end
    else
      {:error, reason} ->
        Logger.error("OAuth callback error: #{reason}")
        text(conn, "Authorization failed: #{reason}")

      error_value ->
        Logger.error("OAuth callback error: unexpected value #{inspect(error_value)}")
        text(conn, "Authorization failed: unexpected error")
    end
  end

  defp fetch_value(map, key) do
    case map[key] do
      nil -> {:error, "#{key} is missing"}
      value -> {:ok, value}
    end
  end

  defp handle_error_response(conn, status_code, body) do
    Logger.error("OAuth token request failed. Status: #{status_code}, Body: #{body}")
    error_message = extract_error_message(body)
    text(conn, "Authorization failed: #{error_message}")
  end

  defp handle_http_error(conn, reason) do
    Logger.error("HTTP request failed: #{inspect(reason)}")
    text(conn, "Authorization failed due to a network error. Please try again.")
  end

  defp extract_error_message(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => error, "error_description" => description}} ->
        "#{error}: #{description}"

      _ ->
        "Unknown error occurred"
    end
  end

  defp token_expired?(conn) do
    case get_session(conn, "oauth_expiration") do
      nil ->
        true

      expiry_datetime ->
        DateTime.compare(DateTime.utc_now(), expiry_datetime) == :gt
    end
  end

  def authenticated?(conn) do
    get_session(conn, "access_token") != nil
  end

  def ensure_authenticated(conn, _opts) do
    if authenticated?(conn) do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page")
      |> redirect(to: Routes.page_path(conn, :index))
      |> halt()
    end
  end

  def check_token_expiration(conn, _opts) do
    case get_session(conn, "oauth_expiration") do
      nil ->
        conn

      expiry_datetime ->
        if DateTime.compare(expiry_datetime, DateTime.utc_now()) == :lt do
          conn
          |> clear_session()
          |> put_flash(:info, "Your session has expired. Please log in again.")
          |> redirect(to: Routes.page_path(conn, :index))
          |> halt()
        else
          conn
        end
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out successfully.")
    |> redirect(to: Routes.page_path(conn, :index))
  end

  # Add any other necessary functions here
end
