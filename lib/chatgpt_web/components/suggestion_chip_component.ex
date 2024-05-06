defmodule ChatgptWeb.SuggestionChipComponent do
  use ChatgptWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="suggestion-chip" role="button" aria-label={"Suggestion " <> @text}>
      {@text}
    </div>
    """
  end
end
