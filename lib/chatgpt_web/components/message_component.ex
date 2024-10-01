defmodule ChatgptWeb.MessageComponent do
  use ChatgptWeb, :live_component

  defp style(:assistant), do: "chat-start"
  defp style(_), do: "chat-end"

  # Updated color scheme for assistant messages
  defp bubble_style(:assistant),
    do: "bg-blue-100 text-gray-800 dark:bg-blue-900 dark:text-gray-200"

  defp bubble_style(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"

  defp process_markdown(markdown) do
    # add list style
    add_list_disc_class = &Earmark.AstTools.merge_atts_in_node(&1, class: "list-disc ml-4")
    add_rounded_class = &Earmark.AstTools.merge_atts_in_node(&1, class: "rounded")

    tsp =
      Earmark.TagSpecificProcessors.new([
        {"ul", add_list_disc_class},
        {"ol", add_list_disc_class},
        {"code", add_rounded_class}
      ])

    m = Earmark.Options.make_options!(registered_processors: [tsp])

    Earmark.as_html!(markdown, m)
  end

  defp render_avatar(%{sender: :user} = assigns) do
    ~H"""
    <div class="w-[30px] flex flex-col relative items-end">
      <div
        style="background-color: rgb(61, 68, 81);"
        class="relative h-[30px] w-[30px] p-1 rounded-sm text-white flex items-center justify-center"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="lucide lucide-square-user-round"
        >
          <path d="M18 21a6 6 0 0 0-12 0" /><circle cx="12" cy="11" r="4" /><rect
            width="18"
            height="18"
            x="3"
            y="3"
            rx="2"
          />
        </svg>
      </div>
    </div>
    """
  end

  defp render_avatar(%{sender: :assistant} = assigns) do
    ~H"""
    <div class="w-[30px] flex flex-col relative items-end">
      <div
        style="background-color: rgb(61, 68, 81);"
        class="relative h-[30px] w-[30px] p-1 rounded-sm text-white flex items-center justify-center"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="lucide lucide-origami"
        >
          <path d="M12 12V4a1 1 0 0 1 1-1h6.297a1 1 0 0 1 .651 1.759l-4.696 4.025" /><path d="m12 21-7.414-7.414A2 2 0 0 1 4 12.172V6.415a1.002 1.002 0 0 1 1.707-.707L20 20.009" /><path d="m12.214 3.381 8.414 14.966a1 1 0 0 1-.167 1.199l-1.168 1.163a1 1 0 0 1-.706.291H6.351a1 1 0 0 1-.625-.219L3.25 18.8a1 1 0 0 1 .631-1.781l4.165.027" />
        </svg>
      </div>
    </div>
    """
  end

  attr :message, :string, required: true
  attr :sender, :string, required: true

  # defp parse_content(content), do: Earmark.as_html!(content)

  # Function clause for when message is a struct
  def render(%{message: %Chatgpt.Message{} = message} = assigns) do
    assigns = assign(assigns, :parsed_content, process_markdown(message.content))

    ~H"""
    <div class={"chat #{style(message.sender)}"}>
      <div class="chat-image avatar">
        <div class="w-10">
          <%= render_avatar(assigns) %>
        </div>
      </div>
      <div class={"chat-bubble shadow-sm space-y-4 p-4 mb-4 rounded w-full #{bubble_style(message.sender)}"}>
        <div class="message-content text-sm md:text-base leading-relaxed">
          <%= raw(@parsed_content) %>
        </div>
        <button
          id={"copy-button-#{message.id}"}
          class="copy-button border border-current rounded p-1 hover:opacity-100 transition-all duration-200"
          phx-hook="CopyMessage"
          data-content={message.content}
          title="Copy to clipboard"
        >
          📋
        </button>
      </div>
    </div>
    """
  end

  # Fallback function clause for when message is a string
  def render(%{message: message} = assigns) when is_binary(message) do
    assigns = assign(assigns, :parsed_content, process_markdown(message))
    assigns = assign(assigns, :message_id, assigns[:id] || "unknown-id")
    assigns = assign(assigns, :sender, assigns[:sender] || :assistant)

    ~H"""
    <div class={"chat #{style(@sender)}"}>
      <div class="chat-image avatar">
        <div class="w-10">
          <%= render_avatar(assigns) %>
        </div>
      </div>
      <div class={"chat-bubble shadow-[0_0_10px_rgba(0,0,0,0.10)] dark:shadow-[0_0_15px_rgba(0,0,0,0.10)] space-y-4 p-4 mb-4 rounded  w-full #{bubble_style(@sender)}"}>
        <div class="message-content text-sm md:text-base leading-relaxed">
          <%= raw(@parsed_content) %>
        </div>
        <%= if @sender != :user do %>
          <button
            id={"copy-button-#{@message_id}"}
            class="copy-button border border-white rounded p-1 hover:opacity-100 transition-all duration-200"
            phx-hook="CopyMessage"
            data-content={message}
            title="Copy to clipboard"
          >
            📋
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
