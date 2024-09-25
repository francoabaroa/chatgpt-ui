The error `Plug.Conn.CookieOverflowError` indicates that the size of the session cookie being sent to the client exceeds the maximum allowed size of 4096 bytes. This usually happens when you're storing too much data in the session. In your case, you're trying to store the entire OAuth token and user profile obtained from Google OAuth into the session, which likely contains large data structures.

Here's the problematic code from your `oauth_callback` function:

```elixir
conn
|> put_session("oauth_google_token", token)
|> put_session("oauth_expiration", expiry_datetime)
|> put_session("google_profile", profile)
|> redirect(to: "/")
```

**Solution**:

To fix this issue, you should store only the minimal necessary data in the session. Instead of storing the entire `token` and `profile` maps, you can extract only the essential information you need, such as the `access_token`, `expires_in`, and the user's `email`.

**Step-by-Step Fix**:

1. **Extract Minimal Data**: Modify your `oauth_callback` function to store only the `access_token`, `expires_in`, and `email`. This reduces the amount of data stored in the session.

2. **Avoid Storing Large Maps**: Do not store the entire `token` and `profile` maps in the session, as they can contain nested structures and unnecessary information.

3. **Update Your Code**:

   Here's how you can modify your `oauth_callback` function:

   ```elixir
   def oauth_callback(conn, %{"code" => code}) do
     with {:ok, token} <- ElixirAuthGoogle.get_token(code, conn),
          %{access_token: access_token} <- token,
          {:ok, profile} <- ElixirAuthGoogle.get_user_profile(access_token),
          %{email: email} <- profile,
          %{expires_in: expires_in} <- token,
          restrict_email_domains? <- Application.get_env(:chatgpt, :restrict_email_domains, false),
          allowed_email_domains <- Application.get_env(:chatgpt, :allowed_email_domains, []) do
       cond do
         # restrict_email_domains set, and domain is found
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
           |> redirect(to: "/")

         {:error, msg} ->
           text(conn, "authorization failed: #{msg}")
       end
     else
       err ->
         text(conn, "authorization failed: #{inspect(err)}")
     end
   end
   ```

4. **Adjust Usage of Session Data**: Update any parts of your application that rely on the session data to reflect these changes. For example, when you need the `access_token` or `email`, retrieve them from the session using the new keys.

5. **Implement Token Expiration Handling**: Ensure that you handle token expiration correctly since you're storing the `expires_in` value. Check if the token has expired before making API calls, and refresh it if necessary.

6. **Security Considerations**: Storing access tokens in cookies (even if they are signed and encrypted) can have security implications. Consider the following best practices:

   - **Use Server-Side Session Storage**: For sensitive data like access tokens, it's safer to store them on the server side (e.g., using an ETS table or database) and only store a reference (like a session ID) in the cookie.
   - **Encrypt Session Cookies**: Make sure your session cookies are encrypted to prevent client-side tampering.

7. **Optional - Server-Side Session Storage**: If you need to store larger amounts of data or want to enhance security, consider using server-side session storage. Phoenix supports this, but it requires additional setup.

**Example of Server-Side Session Storage Setup**:

If you decide to move to server-side session storage, you can use `:ets` as follows:

```elixir
# In your endpoint.ex
plug Plug.Session,
  store: :ets,
  key: "_chatgpt_key",
  signing_salt: "GNrIXLsW",
  same_site: "Lax",
  secure: true, # if you're using HTTPS
  table: :session

# In your application.ex or supervisor
children = [
  # ... other children
  {Plug.Session.ETS, [table: :session]}
]
```

**Note**: Moving to server-side session storage is a more significant change and may not be necessary if you can reduce the data stored in the session.

**Conclusion**:

By reducing the amount of data stored in the session to only what's necessary, you should eliminate the `CookieOverflowError`. This fix ensures your session cookie stays within the size limit and improves the overall security and performance of your application.