defmodule ChatgptWeb.IndexLive do
  alias Chatgpt.Message
  alias ChatgptWeb.LoadingIndicatorComponent
  alias ChatgptWeb.AlertComponent
  use ChatgptWeb, :live_view
  require Logger

  @type state :: %{
          messages: [Message.t()],
          loading: boolean(),
          streaming_message: Message.t(),
          copied_message_id: String.t() | nil
        }

  defp generate_id() do
    :erlang.unique_integer([:positive]) |> to_string()
  end

  @spec dummy_messages() :: [Message.t()]
  defp dummy_messages do
    [
      %Chatgpt.Message{
        content: "Hi there! How can I assist you today?",
        sender: :assistant,
        id: generate_id()
      }
    ]
  end

  @spec initial_state() :: state
  defp initial_state do
    %{
      dummy_messages: dummy_messages() |> fill_random_id(),
      prepend_messages: [],
      messages: [],
      loading: false,
      streaming_message: %Message{content: "", sender: :assistant, id: -1},
      copied_message_id: nil,
      show_drive_search_modal: false,
      drive_search_results: [],
      drive_search_query: "",
      selected_files: []
    }
  end

  defp fill_random_id(messages) do
    Enum.map(messages, fn msg ->
      Map.put(msg, :id, :erlang.unique_integer([:positive]) |> to_string())
    end)
  end

  defp to_atom(s) when is_atom(s), do: s
  defp to_atom(s) when is_binary(s), do: String.to_atom(s)

  defp atom_to_string(s) when is_atom(s), do: Atom.to_string(s)
  defp atom_to_string(s) when is_binary(s), do: s

  def mount(
        _params,
        %{
          "model" => model,
          "models" => models,
          "mode" => :scenario,
          "scenario" => scenario
        } = session,
        socket
      ) do
    {:ok, pid} = Chatgpt.MessageStore.start_link([])

    selected_model =
      case scenario do
        %{force_model: force_model_id} ->
          atom_to_string(force_model_id)

        _ ->
          model
      end

    {:ok,
     socket
     |> assign(initial_state())
     |> assign(%{
       message_store_pid: pid,
       prepend_messages: scenario.messages,
       dummy_messages: [
         %Chatgpt.Message{
           content: scenario.description,
           sender: :assistant,
           id: generate_id()
         }
       ],
       model: selected_model,
       models: models,
       active_model: Enum.find(models, &(&1.id == to_atom(selected_model))),
       scenarios: Map.get(session, "scenarios"),
       scenario: scenario,
       mode: :scenario,
       show_drive_search_modal: false,
       drive_search_results: [],
       drive_search_query: "",
       # Add this line
       access_token: session["access_token"]
     })}
  end

  def mount(_params, %{"model" => model, "models" => models} = session, socket) do
    {:ok, pid} = Chatgpt.MessageStore.start_link([])

    {:ok,
     socket
     |> assign(initial_state())
     |> assign(%{
       model: model,
       message_store_pid: pid,
       dummy_messages: dummy_messages() |> fill_random_id(),
       active_model: Enum.find(models, &(&1.id == to_atom(model))),
       models: models,
       scenarios: Map.get(session, "scenarios"),
       mode: :chat,
       # Explicitly set this here
       show_drive_search_modal: false,
       # Add this line
       access_token: session["access_token"]
     })}
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:show_drive_search_modal, false)
      |> assign(:drive_search_results, [])
      |> assign(:drive_search_query, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("open_drive_search", _params, socket) do
    {:noreply, assign(socket, show_drive_search_modal: true)}
  end

  @impl true
  def handle_event("search_drive", %{"query" => query}, socket) do
    # Use the access_token from the socket assigns
    token = socket.assigns.access_token

    case Chatgpt.Drive.search_files(token, query) do
      {:ok, files} ->
        formatted_results =
          Enum.map(files, fn file ->
            %{id: file.id, name: file.name}
          end)

        {:noreply,
         assign(socket, drive_search_results: formatted_results, drive_search_query: query)}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Error searching files: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("close_drive_search_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(show_drive_search_modal: false)
     |> assign(drive_search_query: "")
     |> assign(drive_search_results: [])}
  end

  @impl true
  def handle_event("add_selected_files", %{"selected_files" => selected_file_ids}, socket) do
    token = socket.assigns.access_token

    # Fetch file info and store in selected_files
    files_with_content =
      Enum.map(selected_file_ids, fn file_id ->
        case Chatgpt.Drive.get_file_info_and_content(token, file_id) do
          {:ok, file, content} ->
            %{id: file.id, name: file.name, content: content}

          {:error, reason} ->
            Logger.error(
              "Failed to get file content for file_id: #{file_id}. Reason: #{inspect(reason)}"
            )

            nil
        end
      end)
      |> Enum.filter(& &1)

    if Enum.empty?(files_with_content) do
      {:noreply,
       socket
       |> put_flash(:error, "Failed to retrieve content for the selected files.")}
    else
      {:noreply,
       socket
       |> assign(selected_files: socket.assigns.selected_files ++ files_with_content)
       |> assign(show_drive_search_modal: false)
       |> put_flash(:info, "Added #{length(files_with_content)} file(s) to your message")}
    end
  end

  # Handle the case when no files are selected
  def handle_event("add_selected_files", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "No files selected")}
  end

  def handle_event("close_drive_search", _params, socket) do
    {:noreply,
     socket
     |> assign(show_drive_search_modal: false)
     |> assign(drive_search_query: "")
     |> assign(drive_search_results: [])}
  end

  @impl true
  def handle_event("remove_selected_file", %{"file-id" => file_id}, socket) do
    updated_files = Enum.reject(socket.assigns.selected_files, fn file -> file.id == file_id end)
    {:noreply, assign(socket, selected_files: updated_files)}
  end

  def handle_info({:set_error, msg}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, msg)
     |> push_event("newmessage", %{})}
  end

  def handle_info(:unset_error, socket) do
    {:noreply,
     socket
     |> clear_flash(:error)
     |> push_event("newmessage", %{})}
  end

  def handle_info({:add_message, msg}, socket) do
    new_id = Enum.count(socket.assigns.messages) + 1
    msg = Map.put(msg, :id, new_id)

    {:noreply,
     socket
     |> assign(%{messages: socket.assigns.messages ++ [msg]})
     |> push_event("newmessage", %{})}
  end

  def handle_info(:sync_messages, socket) do
    msgs = Chatgpt.MessageStore.get_messages(socket.assigns.message_store_pid)

    {:noreply,
     socket
     |> assign(%{messages: msgs})
     |> push_event("newmessage", %{})}
  end

  def handle_info({:handle_stream_chunk, nil}, socket) do
    {:noreply, socket}
  end

  def handle_info({:handle_stream_chunk, text}, socket) do
    streaming_message =
      socket.assigns.streaming_message
      |> Map.put(:content, socket.assigns.streaming_message.content <> text)

    {:noreply,
     socket
     |> assign(streaming_message: streaming_message)}
  end

  def handle_info(:commit_streaming_message, socket) do
    msg = socket.assigns.streaming_message

    Chatgpt.MessageStore.add_message(socket.assigns.message_store_pid, %Chatgpt.Message{
      content: msg.content,
      sender: :assistant,
      id: Chatgpt.MessageStore.get_next_id(socket.assigns.message_store_pid)
    })

    Process.send(self(), :stop_loading, [])

    Process.send(self(), :sync_messages, [])

    {:noreply,
     socket
     |> assign(%{
       streaming_message: %Message{content: "", sender: :assistant, id: -1}
     })
     |> push_event("newmessage", %{})}
  end

  def handle_info({:update_messages, msgs}, socket) do
    {:noreply, assign(socket, %{messages: msgs})}
  end

  def handle_info(:stop_loading, socket) do
    {:noreply, assign(socket, %{loading: false})}
  end

  def handle_info(:start_loading, socket) do
    {:noreply, assign(socket, %{loading: true})}
  end

  # Message when loading should not get processed
  def handle_info({:msg_submit, text}, %{assigns: %{loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_info({:msg_submit, text}, %{assigns: %{loading: false}} = socket) do
    self = self()

    Process.send(self, :start_loading, [])
    Process.send(self, :sync_messages, [])

    model = Map.get(socket.assigns, :model)

    # Append selected file contents to the message
    full_message = text <> append_selected_files_content(socket.assigns.selected_files)

    # Add new message to message_store
    Chatgpt.MessageStore.add_message(socket.assigns.message_store_pid, %Chatgpt.Message{
      content: full_message,
      sender: :user,
      id: Chatgpt.MessageStore.get_next_id(socket.assigns.message_store_pid)
    })

    Process.send(self, :sync_messages, [])

    handle_chunk_callback = fn
      # Callback for stream finished
      :finish ->
        Process.send(self, :commit_streaming_message, [])

      # Callback for delta data
      {:data, data} ->
        Process.send(self, {:handle_stream_chunk, data}, [])

      {:error, err} ->
        Process.send(self, {:set_error, "#{inspect(err)}"}, [])
        Process.send(self, :stop_loading, [])
    end

    messages =
      case socket.assigns.mode do
        :chat ->
          socket.assigns.prepend_messages ++
            Chatgpt.MessageStore.get_messages(socket.assigns.message_store_pid)

        :scenario ->
          case socket.assigns.scenario.keep_context do
            true ->
              socket.assigns.prepend_messages ++
                Chatgpt.MessageStore.get_messages(socket.assigns.message_store_pid)

            false ->
              socket.assigns.prepend_messages ++
                Chatgpt.MessageStore.get_recent_messages(socket.assigns.message_store_pid, 1)
          end
      end

    llm = Chatgpt.LLM.get_provider(socket.assigns.active_model.provider)
    llm.do_complete(messages, model, handle_chunk_callback)

    {:noreply, socket |> assign(:loading, true) |> assign(:selected_files, []) |> clear_flash()}
  end

  # Helper function to append selected file contents
  defp append_selected_files_content(selected_files) do
    selected_files
    |> Enum.map(fn file ->
      tag_name = file.name |> String.replace(~r/[^a-zA-Z0-9]+/, "_") |> String.downcase()
      "\n\n<#{tag_name}>\n#{file.content}\n</#{tag_name}>"
    end)
    |> Enum.join("\n")
  end

  @impl true
  def handle_info({:reset_copied, message_id}, socket) do
    if socket.assigns.copied_message_id == message_id do
      {:noreply, assign(socket, :copied_message_id, nil)}
    else
      {:noreply, socket}
    end
  end

  defp schedule_copied_reset(socket, message_id) do
    Process.send_after(self(), {:reset_copied, message_id}, 2000)
    socket
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="chatgpt" class="flex flex-col h-full relative">
      <!-- Chat messages -->
      <div class="flex-grow overflow-y-auto px-4 pb-24 pt-16">
        <!-- Search button -->
        <div class="absolute top-0 right-0 z-20 p-4 bg-gray-50 dark:bg-gray-900">
          <button phx-click="open_drive_search" class="btn btn-primary">
            <svg
              class="w-6 h-6"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
              >
              </path>
            </svg>
          </button>
        </div>
        <.live_component
          module={ChatgptWeb.MessageListComponent}
          messages={@dummy_messages ++ @messages ++ [@streaming_message]}
          id="message-list"
          copied_message_id={@copied_message_id}
        />

        <%= if Phoenix.Flash.get(@flash, :error) do %>
          <div class="my-4">
            <AlertComponent.render text={Phoenix.Flash.get(@flash, :error)} />
          </div>
        <% end %>

        <%= if @loading do %>
          <div class="my-4">
            <LoadingIndicatorComponent.render />
          </div>
        <% end %>
      </div>
      <!-- Input area -->
      <div class="sticky bottom-0 left-0 right-0 bg-white dark:bg-gray-800 border-t dark:border-gray-700 p-4">
        <.live_component
          on_submit={fn val -> Process.send(self(), {:msg_submit, val}, []) end}
          module={ChatgptWeb.TextboxComponent}
          disabled={@loading}
          id="textbox"
          selected_files={@selected_files}
          #
          Add
          this
          line
        />
      </div>
      <!-- Drive search modal -->
      <%= if @show_drive_search_modal do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center">
          <div class="bg-white dark:bg-gray-800 rounded-lg p-6 w-full max-w-md">
            <div class="flex justify-between items-center mb-4">
              <h2 class="text-xl font-bold">Search Google Drive</h2>
              <button phx-click="close_drive_search_modal" class="text-gray-500 hover:text-gray-700">
                &times;
              </button>
            </div>
            <form phx-submit="search_drive" class="mb-4">
              <input
                type="text"
                name="query"
                value={@drive_search_query}
                placeholder="Enter search query"
                class="w-full p-2 border rounded"
              />
              <button type="submit" class="mt-2 w-full bg-blue-500 text-white p-2 rounded">
                Search
              </button>
            </form>

            <form phx-submit="add_selected_files">
              <div class="search-results">
                <%= if length(@drive_search_results) > 0 do %>
                  <%= for result <- @drive_search_results do %>
                    <div class="flex items-center mb-2">
                      <input
                        type="checkbox"
                        name="selected_files[]"
                        value={result.id}
                        id={"file-#{result.id}"}
                        class="mr-2"
                      />
                      <label for={"file-#{result.id}"}><%= result.name %></label>
                    </div>
                  <% end %>
                  <button type="submit" class="w-full bg-green-500 text-white p-2 rounded mt-4">
                    Add Selected Files
                  </button>
                <% else %>
                  <p class="text-gray-500">No results found.</p>
                <% end %>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
