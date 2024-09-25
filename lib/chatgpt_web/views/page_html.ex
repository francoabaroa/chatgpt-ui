defmodule ChatgptWeb.PageHTML do
  use ChatgptWeb, :html

  embed_templates("templates/*")

  def drive_files(assigns) do
    ~H"""
    <div>
      <h1>Drive Files</h1>
      <ul>
        <%= for file <- @files do %>
          <li><%= file.name %></li>
        <% end %>
      </ul>
    </div>
    """
  end
end
