defmodule Chatgpt.Ets.SessionStore do
  @behaviour Plug.Session.Store

  alias Chatgpt.Ets.SessionIdManager

  @impl true
  def init(_opts) do
    :ok
  end

  @impl true
  def get(_conn, cookie, _opts) do
    case SessionIdManager.get(cookie) do
      {:ok, data} -> {cookie, data}
      {:error, :not_found} -> {nil, %{}}
    end
  end

  @impl true
  def put(_conn, nil, data, _opts) do
    cookie = generate_session_id()
    SessionIdManager.put(cookie, data)
    cookie
  end

  @impl true
  def put(_conn, cookie, data, _opts) do
    SessionIdManager.put(cookie, data)
    cookie
  end

  @impl true
  def delete(_conn, cookie, _opts) do
    SessionIdManager.delete(cookie)
    :ok
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
