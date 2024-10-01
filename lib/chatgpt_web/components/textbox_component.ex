defmodule ChatgptWeb.TextboxComponent do
  use ChatgptWeb, :live_component

  defp new_form(text \\ ""), do: to_form(%{"text" => text, "rand" => UUID.uuid4()}, as: :main)

  def mount(socket) do
    {:ok,
     socket
     |> assign(form: new_form(), text: "")}
  end

  def update(%{append_text: append_text}, socket) do
    current_text = socket.assigns.form.params["text"] || ""
    updated_text = current_text <> "\n\n" <> append_text
    {:ok, assign(socket, form: new_form(updated_text))}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def handle_event("onsubmit", %{"main" => %{"text" => text}}, socket) do
    if String.length(text) >= 1 and socket.assigns.disabled == false do
      socket.assigns.on_submit.(text)
      {:noreply, socket |> assign(form: new_form())}
    else
      {:noreply, socket}
    end
  end

  attr :field, Phoenix.HTML.FormField
  attr :text, :string
  attr :myself, :any
  attr :disabled, :boolean
  attr :selected_files, :list, default: []

  def textarea(assigns) do
    assigns =
      assign(assigns, :onkeydown, """
      if(event.keyCode == 13 && event.shiftKey == false) {
      		document.getElementById('submitbtn').click();
      	 return false;}
      """)

    ~H"""
    <textarea
      tabindex="0"
      style="max-height: 200px; height: 96px;"
      class="m-0 w-full resize-none border-0 bg-transparent p-0 pr-7 focus:ring-0 focus-visible:ring-0 dark:bg-transparent pl-2 md:pl-0"
      placeholder="Enter your message..."
      id={@field.id}
      name={@field.name}
      phx-target={@myself}
      onkeydown={@onkeydown}
    ><%= @field.value %></textarea>
    """
  end

  attr :on_submit, :any, required: true
  attr :disabled, :boolean, required: true
  attr :selected_files, :list, default: []

  def render(assigns) do
    ~H"""
    <div class="message-composer">
      <!-- Display selected files -->
      <div class="selected-files flex flex-wrap mb-2">
        <%= for file <- @selected_files do %>
          <div class="file-badge flex items-center mr-2 mb-2 bg-gray-200 rounded px-2 py-1 relative group">
            <span class="file-name mr-1" title={preview_content(file.content)}>
              <%= file.name %>
            </span>
            <button
              type="button"
              phx-click="remove_selected_file"
              phx-value-file-id={file.id}
              class="remove-file text-red-500 hover:text-red-700"
            >
              &times;
            </button>
            <div class="preview-popup absolute left-0 top-full mt-2 p-2 bg-white border rounded shadow-lg hidden group-hover:block z-10">
              <p class="text-sm"><%= preview_content(file.content) %></p>
            </div>
          </div>
        <% end %>
      </div>

      <p><%= @text %></p>
      <.form
        class="stretch mx-2 flex flex-row gap-3 last:mb-2 md:mx-4 md:last:mb-6 lg:mx-auto lg:max-w-3xl"
        phx-target={@myself}
        phx-submit="onsubmit"
        for={@form}
      >
        <div class="flex flex-col w-full py-2 flex-grow md:py-3 md:pl-4 relative border border-black/10 bg-white dark:border-gray-900/50 dark:text-white dark:bg-gray-700 rounded-md shadow-[0_0_10px_rgba(0,0,0,0.10)] dark:shadow-[0_0_15px_rgba(0,0,0,0.10)]">
          <.textarea disabled={@disabled} field={@form[:text]} myself={@myself} text={@text} />
          <button
            id="submitbtn"
            class="absolute p-1 rounded-md text-gray-500 bottom-1.5 md:bottom-2.5 hover:bg-gray-100 dark:hover:text-gray-400 dark:hover:bg-gray-900 disabled:hover:bg-transparent dark:disabled:hover:bg-transparent right-1 md:right-2"
          >
            <svg
              stroke="currentColor"
              fill="none"
              stroke-width="2"
              viewBox="0 0 24 24"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="h-4 w-4 mr-1"
              height="1em"
              width="1em"
              xmlns="http://www.w3.org/2000/svg"
            >
              <line x1="22" y1="2" x2="11" y2="13"></line>
              <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
            </svg>
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp preview_content(content) do
    content
    |> String.split(~r/\s+/)
    |> Enum.take(30)
    |> Enum.join(" ")
    |> Kernel.<>("...")
  end
end
