defmodule ChatgptWeb.ErrorHTML do
  use ChatgptWeb, :html

  embed_templates "error_html/*"

  def render("401.html", _assigns) do
    "Unauthorized - Please log in to access this page"
  end

  # ... other error functions ...
end
