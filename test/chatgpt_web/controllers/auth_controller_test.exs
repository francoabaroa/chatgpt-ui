defmodule ChatgptWeb.AuthControllerTest do
  use ChatgptWeb.ConnCase

  # Mock ElixirAuthGoogle functions for testing
  import Mox
  setup :verify_on_exit!

  test "oauth_callback success", %{conn: conn} do
    expect(ElixirAuthGoogle.MockClient, :get_token, fn _code, _conn ->
      {:ok, %{access_token: "mock_token", expires_in: 3600}}
    end)

    expect(ElixirAuthGoogle.MockClient, :get_user_profile, fn _token ->
      {:ok, %{email: "test@incurator.io"}}
    end)

    conn = get(conn, Routes.auth_path(conn, :oauth_callback, code: "mock_code"))
    assert redirected_to(conn) == "/"
    assert get_session(conn, "email") == "test@incurator.io"
  end

  # ... more tests ...
end
