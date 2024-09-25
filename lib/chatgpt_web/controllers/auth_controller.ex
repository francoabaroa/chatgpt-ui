defmodule ChatgptWeb.AuthController do
  use ChatgptWeb, :controller
  require Logger

  def oauth(conn, _params) do
    scopes = Application.get_env(:elixir_auth_google, :scopes)
    oauth_google_url = ElixirAuthGoogle.generate_oauth_url(conn)
    redirect(conn, external: oauth_google_url)
  end

  def oauth_callback(conn, %{"code" => code}) do
    with {:ok, token} <- ElixirAuthGoogle.get_token(code, conn),
         %{access_token: access_token, expires_in: expires_in} <- token,
         {:ok, profile} <- ElixirAuthGoogle.get_user_profile(access_token),
         %{email: email} <- profile do
      restrict_email_domains? = Application.get_env(:chatgpt, :restrict_email_domains, false)
      allowed_email_domains = Application.get_env(:chatgpt, :allowed_email_domains, [])

      cond do
        restrict_email_domains? and
            Enum.find(allowed_email_domains, &String.contains?(email, &1)) == nil ->
          {:error, "email not allowed"}

        true ->
          :ok
      end
      |> case do
        :ok ->
          expiry_datetime = DateTime.add(DateTime.utc_now(), expires_in, :second)

          conn
          |> put_session("access_token", access_token)
          |> put_session("oauth_expiration", expiry_datetime)
          |> put_session("email", email)
          |> configure_session(renew: true)
          |> redirect(to: "/")

        {:error, msg} ->
          text(conn, "Authorization failed: #{msg}")
      end
    else
      {:error, reason} ->
        Logger.error("OAuth callback error: #{inspect(reason)}")
        text(conn, "Authorization failed: #{inspect(reason)}")

      err ->
        Logger.error("Unexpected OAuth callback error: #{inspect(err)}")
        text(conn, "Authorization failed: Unexpected error occurred")
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
