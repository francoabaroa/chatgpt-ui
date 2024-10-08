defmodule ChatgptWeb.IndexLive do
  alias Chatgpt.Message
  alias ChatgptWeb.LoadingIndicatorComponent
  alias ChatgptWeb.AlertComponent
  use ChatgptWeb, :live_view
  require Logger
  alias Chatgpt.RealtimeApiClient

  # TODO why on_submit={fn val -> send(self(), {:msg_submit, val}) end} needed?

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
      selected_files: [],
      additional_data: %{},
      function_calls: [],
      function_outputs: []
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
       access_token: session["access_token"],
       additional_data: %{},
       function_calls: [],
       function_outputs: []
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
       session_id: nil,
       scenarios: Map.get(session, "scenarios"),
       mode: :chat,
       # Explicitly set this here
       show_drive_search_modal: false,
       # Add this line
       access_token: session["access_token"],
       additional_data: %{},
       function_calls: [],
       function_outputs: []
     })}
  end

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(initial_state()) |> assign(:api_client_pid, nil)}
  end

  @impl true
  def handle_event("open_drive_search", _params, socket) do
    {:noreply, assign(socket, show_drive_search_modal: true)}
  end

  @impl true
  def handle_event("start_voice_chat", _params, socket) do
    {:ok, api_client_pid} = RealtimeApiClient.start_link(channel_pid: self())

    {:noreply,
     socket
     |> assign(:api_client_pid, api_client_pid)
     |> push_event("voice_chat_started", %{})}
  end

  @impl true
  def handle_event("stop_voice_chat", _params, socket) do
    if socket.assigns[:api_client_pid] do
      Process.exit(socket.assigns.api_client_pid, :normal)

      {:noreply,
       socket
       |> assign(:voice_chat_active, false)
       |> assign(:api_client_pid, nil)
       |> push_event("voice_chat_stopped", %{})}
    else
      {:noreply, socket |> put_flash(:error, "No active voice chat to stop")}
    end
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
  def handle_event("send_text", %{"text" => text}, socket) do
    # Send text to RealtimeChannel
    ChatgptWeb.Endpoint.broadcast_from(
      socket.assigns.myself,
      "realtime:" <> socket.id,
      "text_input",
      %{"text" => text}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_audio", %{"audio" => audio_data}, socket) do
    RealtimeApiClient.handle_audio_input(socket.assigns.api_client, audio_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("interrupt_voice_chat", _params, socket) do
    if socket.assigns[:api_client] do
      WebSockex.cast(socket.assigns.api_client, :interrupt)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:realtime_event, event_type, payload}, socket) do
    case event_type do
      :session_created ->
        Logger.info("Session created: #{inspect(payload["session"])}")
        {:noreply, socket}

      :session_updated ->
        Logger.info("Session updated: #{inspect(payload["session"])}")
        {:noreply, socket}

      :speech_started ->
        {:noreply, push_event(socket, "speech_started", %{})}

      :speech_stopped ->
        {:noreply, push_event(socket, "speech_stopped", %{})}

      :audio_buffer_committed ->
        {:noreply, push_event(socket, "audio_committed", %{})}

      :conversation_item_created ->
        new_message = extract_message_from_event(payload)
        {:noreply, assign(socket, messages: socket.assigns.messages ++ [new_message])}

      :text_delta ->
        streaming_message =
          socket.assigns.streaming_message
          |> Map.update(:content, "", &(&1 <> payload["delta"]))

        {:noreply, assign(socket, streaming_message: streaming_message)}

      :audio_delta ->
        {:noreply, push_event(socket, "audio_delta", %{"delta" => payload["delta"]})}

      :response_done ->
        Process.send(self(), :commit_streaming_message, [])
        {:noreply, socket}

      :response_created ->
        {:noreply, socket}

      :output_item_added ->
        {:noreply, socket}

      :content_part_added ->
        {:noreply, socket}

      :audio_transcript_delta ->
        {:noreply, socket}

      :audio_done ->
        {:noreply, socket}

      :audio_transcript_done ->
        {:noreply, socket}

      :content_part_done ->
        {:noreply, socket}

      :output_item_done ->
        {:noreply, socket}

      :rate_limits_updated ->
        {:noreply, socket}

      _ ->
        Logger.warn("LiveView Unhandled event type: #{event_type}")
        {:noreply, socket}
    end
  end

  defp extract_message_from_event(event) do
    %Message{
      content: event["item"]["content"],
      sender: String.to_atom(event["item"]["role"]),
      id: generate_id()
    }
  end

  defp extract_function_call_from_event(event) do
    %{
      name: event["function_call"]["name"],
      arguments: event["function_call"]["arguments"],
      id: generate_id()
    }
  end

  defp extract_function_output_from_event(event) do
    %{
      output: event["output"],
      id: generate_id()
    }
  end

  @impl true
  def handle_event("send_audio_chunk", %{"audio" => base64_audio}, socket) do
    if socket.assigns[:api_client_pid] do
      WebSockex.cast(socket.assigns.api_client_pid, {:send_audio_chunk, base64_audio})
      {:noreply, socket}
    else
      {:noreply, socket |> put_flash(:error, "Voice chat is not active")}
    end
  end

  @impl true
  def handle_event("commit_audio", _params, socket) do
    if socket.assigns[:api_client_pid] do
      WebSockex.cast(socket.assigns.api_client_pid, :send_audio_commit)
      {:noreply, socket}
    else
      {:noreply, socket |> put_flash(:error, "Voice chat is not active")}
    end
  end

  def handle_info({:realtime_event, event_type, payload}, socket) do
    event_type_str = Atom.to_string(event_type)

    case event_type_str do
      "session_created" ->
        Logger.info("Session created: #{inspect(payload["session"])}")
        {:noreply, socket}

      "session_updated" ->
        Logger.info("Session updated: #{inspect(payload["session"])}")
        {:noreply, socket}

      "speech_started" ->
        {:noreply, push_event(socket, "speech_started", %{})}

      "speech_stopped" ->
        {:noreply, push_event(socket, "speech_stopped", %{})}

      "audio_buffer_committed" ->
        {:noreply, push_event(socket, "audio_committed", %{})}

      "conversation_item_created" ->
        new_message = extract_message_from_event(payload)
        {:noreply, assign(socket, messages: socket.assigns.messages ++ [new_message])}

      "text_delta" ->
        streaming_message =
          socket.assigns.streaming_message
          |> Map.update(:content, "", &(&1 <> payload["delta"]))

        {:noreply, assign(socket, streaming_message: streaming_message)}

      "audio_delta" ->
        {:noreply, push_event(socket, "audio_delta", %{"delta" => payload["delta"]})}

      "audio_transcript_delta" ->
        # Update the last message's transcript with the new delta
        updated_messages =
          update_last_message_transcript(socket.assigns.messages, payload["delta"])

        {:noreply, assign(socket, messages: updated_messages)}

      "response_done" ->
        Process.send(self(), :commit_streaming_message, [])
        {:noreply, socket}

      "response_created" ->
        Logger.info("Response created: #{inspect(payload["response"])}")
        {:noreply, socket}

      "output_item_added" ->
        Logger.info("Output item added: #{inspect(payload["item"])}")
        {:noreply, socket}

      "content_part_added" ->
        Logger.info("Content part added: #{inspect(payload["part"])}")
        {:noreply, socket}

      "audio_done" ->
        Logger.info("Audio done")
        {:noreply, socket}

      "audio_transcript_done" ->
        Logger.info("Audio transcript done")
        {:noreply, socket}

      "content_part_done" ->
        Logger.info("Content part done")
        {:noreply, socket}

      "output_item_done" ->
        Logger.info("Output item done")
        {:noreply, socket}

      "rate_limits_updated" ->
        Logger.info("Rate limits updated: #{inspect(payload["rate_limits"])}")
        {:noreply, socket}

      _ ->
        Logger.warn("LiveView Unhandled event type: #{event_type_str}")
        {:noreply, socket}
    end
  end

  defp handle_conversation_item_created(socket, payload) do
    content_parts = payload["item"]["content"]

    new_message = %{
      content: content_parts,
      sender: payload["item"]["role"],
      id: generate_id()
    }

    socket
    |> update(:messages, fn messages -> messages ++ [new_message] end)
    |> push_event("new_message", %{message: new_message})
  end

  defp handle_audio_transcript_delta(socket, payload) do
    # Update the last message's transcript instead of using a separate :transcription assign
    updated_messages = update_last_message_transcript(socket.assigns.messages, payload["delta"])

    socket
    |> assign(:messages, updated_messages)
    |> push_event("transcription_update", %{delta: payload["delta"]})
  end

  defp update_last_message_transcript(messages, delta) do
    case List.last(messages) do
      %{sender: "user", content: content} when is_list(content) ->
        updated_content = update_content_with_delta(content, delta)
        List.update_at(messages, -1, fn msg -> %{msg | content: updated_content} end)

      _ ->
        messages
    end
  end

  defp update_content_with_delta(content, delta) do
    Enum.map(content, fn
      %{"type" => "input_audio", "transcript" => transcript} = part ->
        %{part | "transcript" => (transcript || "") <> delta}

      other ->
        other
    end)
  end

  @impl true
  def handle_event("send_audio_chunk", %{"audio" => base64_audio}, socket) do
    if socket.assigns[:api_client] do
      RealtimeApiClient.handle_audio_input(socket.assigns.api_client, base64_audio)
    else
      Logger.error("API client not available")
    end

    {:noreply, socket}
  end

  # Add these new handle_info functions:

  def handle_info({:realtime, "response.audio.delta", event}, socket) do
    {:noreply, push_event(socket, "audio_delta", %{"delta" => event["delta"]})}
  end

  def handle_info({:realtime, "response.text.delta", event}, socket) do
    {:noreply, push_event(socket, "text_delta", %{"delta" => event["delta"]})}
  end

  def handle_info({:realtime, "response.end", _event}, socket) do
    {:noreply, push_event(socket, "response_end", %{})}
  end

  def handle_info({:realtime, "error", event}, socket) do
    {:noreply, socket |> put_flash(:error, "API Error: #{event["message"]}")}
  end

  # Add a generic handler for events that need standard processing
  def handle_info({:realtime, event_type, event}, socket)
      when event_type in [
             "session.created",
             "session.updated",
             "conversation.item.created",
             "conversation.item.updated",
             "conversation.item.completed",
             "input_audio_buffer.speech_stopped",
             "input_audio_buffer.committed",
             "response.created",
             "response.output_item.added",
             "response.content_part.added"
           ] do
    Logger.info("LiveView Received API event: #{event_type}")
    # You can add any standard processing here
    {:noreply, socket}
  end

  # Optionally, add a catch-all handler for any unhandled events
  def handle_info({:realtime, event_type, event}, socket) do
    Logger.warn("LiveView Unhandled API event: #{event_type}")
    {:noreply, socket}
  end

  # Add these new handle_info clauses:

  def handle_info({:realtime, "session.created", event}, socket) do
    Logger.info("Session created: #{inspect(event["session"])}")
    {:noreply, socket}
  end

  def handle_info({:realtime, "session.updated", event}, socket) do
    Logger.info("Session updated: #{inspect(event["session"])}")
    {:noreply, socket}
  end

  # Update the existing handle_info clause for "input_audio_buffer.speech_started"
  def handle_info({:realtime, "input_audio_buffer.speech_started", event}, socket) do
    Logger.info("Speech started: #{inspect(event)}")
    {:noreply, push_event(socket, "speech_started", %{})}
  end

  # Replace the existing handle_info clause for "response.audio_transcript.delta" with this:

  def handle_info({:realtime, "response.audio_transcript.delta", event}, socket) do
    Logger.info("Audio transcript delta: #{inspect(event)}")

    updated_messages = update_last_message_transcript(socket.assigns.messages, event["delta"])

    {:noreply,
     socket
     |> assign(:messages, updated_messages)
     |> push_event("audio_transcript_delta", %{delta: event["delta"]})}
  end

  def handle_info(
        {:realtime, "conversation.item.input_audio_transcription.completed", event},
        socket
      ) do
    Logger.info("Audio transcription completed: #{inspect(event)}")
    # Update the corresponding message with the transcript
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="chatgpt" class="flex flex-col h-full relative">
      <!-- Chat messages -->
      <div class="flex-grow overflow-y-auto px-4 pb-24 pt-16">
        <!-- Search and Voice Chat buttons -->
        <div class="absolute top-0 right-0 z-20 p-4 bg-gray-50 dark:bg-gray-900 flex">
          <button phx-click="open_drive_search" class="btn btn-primary mr-2">
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
          <div id="voice-chat" phx-hook="VoiceChat">
            <!-- Voice Chat Controls -->
            <div id="voice-chat-controls" class="flex space-x-2 mt-4">
              <button id="start-voice-chat" phx-click="start_voice_chat" class="btn btn-primary">
                Start Voice Chat
              </button>
              <button
                id="stop-recording"
                phx-click="stop_voice_chat"
                style="display: none;"
                class="btn btn-secondary"
              >
                Stop Recording
              </button>
              <button
                id="interrupt-voice-chat"
                phx-click="interrupt_voice_chat"
                style="display: none;"
                class="btn btn-danger"
              >
                Interrupt
              </button>
            </div>
          </div>
        </div>
        <.live_component
          module={ChatgptWeb.MessageListComponent}
          messages={@messages ++ [@streaming_message]}
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
        <!-- Function calls -->
        <%= if length(@function_calls) > 0 do %>
          <div class="my-4">
            <h3 class="text-lg font-semibold">Function Calls</h3>
            <%= for call <- @function_calls do %>
              <div class="bg-gray-100 dark:bg-gray-700 p-2 rounded mt-2">
                <p><strong><%= call.name %></strong></p>
                <pre><code><%= Jason.encode!(call.arguments, pretty: true) %></code></pre>
              </div>
            <% end %>
          </div>
        <% end %>
        <!-- Function outputs -->
        <%= if length(@function_outputs) > 0 do %>
          <div class="my-4">
            <h3 class="text-lg font-semibold">Function Outputs</h3>
            <%= for output <- @function_outputs do %>
              <div class="bg-gray-100 dark:bg-gray-700 p-2 rounded mt-2">
                <%= if is_binary(output.output) do %>
                  <p><%= output.output %></p>
                <% else %>
                  <pre><code><%= Jason.encode!(output.output, pretty: true) %></code></pre>
                <% end %>
              </div>
            <% end %>
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

  # Add this new terminate/2 function near the end of the module:

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:api_client_pid] && Process.alive?(socket.assigns.api_client_pid) do
      Process.exit(socket.assigns.api_client_pid, :normal)
    end

    :ok
  end
end
