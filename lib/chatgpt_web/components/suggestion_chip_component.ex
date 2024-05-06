defmodule ChatGptUiWeb.SuggestionChipComponent do
  use ChatGptUiWeb, :live_component

  @impl true
  def render(assigns) do
    ~L"""
    <div class="suggestion-chip">
      <%= @text %>
    </div>
    """
  end
end
