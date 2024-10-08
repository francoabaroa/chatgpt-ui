defmodule ChatgptWeb.RealtimeChannel do
  use Phoenix.Channel
  require Logger

  @impl true
  def join("realtime:lobby", _message, socket) do
    case Chatgpt.RealtimeApiClient.start_link(channel_pid: self()) do
      {:ok, pid} ->
        {:ok, assign(socket, :api_client, pid)}

      {:error, reason} ->
        Logger.error("Failed to start RealtimeApiClient: #{inspect(reason)}")
        {:error, %{reason: "Failed to initialize API client"}}
    end
  end

  @impl true
  def handle_in("send_audio_chunk", %{"audio" => base64_audio}, socket) do
    WebSockex.cast(socket.assigns.api_client, {:send_audio_chunk_base64, base64_audio})
    {:noreply, socket}
  end

  @impl true
  def handle_in("send_text", %{"text" => text}, socket) do
    WebSockex.cast(socket.assigns.api_client, {:send_text_input, text})
    {:noreply, socket}
  end

  @impl true
  def handle_in("interrupt", _params, socket) do
    WebSockex.cast(socket.assigns.api_client, :interrupt)
    {:noreply, socket}
  end

  @impl true
  def handle_in("commit_audio", _params, socket) do
    WebSockex.cast(socket.assigns.api_client, :send_audio_commit)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:realtime_event, event}, socket) when is_map(event) do
    case event do
      %{"type" => type} ->
        handle_event_by_type(type, event, socket)

      _ ->
        Logger.warn("Realtime Channel Unhandled event: #{inspect(event)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:realtime_event, event_type, event}, socket) when is_atom(event_type) do
    handle_event_by_type(Atom.to_string(event_type), event, socket)
  end

  @impl true
  def handle_info({:api_error, error}, socket) do
    push(socket, "api_error", error)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:send_session_create, socket) do
    event = %{
      type: "session.create",
      session: %{
        # ... other session parameters ...
        tools: [
          %{
            type: "function",
            name: "get_weather",
            description: "Gets the weather for a given location.",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string", description: "The location to get weather for."}
              },
              required: ["location"]
            }
          }
        ],
        tool_choice: "auto"
      }
    }

    GenServer.cast(socket.assigns.api_client, {:send_json, event})
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if Process.alive?(socket.assigns.api_client) do
      GenServer.stop(socket.assigns.api_client)
    end

    :ok
  end

  defp handle_event_by_type(type, event, socket) do
    case type do
      "session.created" ->
        Logger.info("Session created: #{inspect(event["session"])}")
        push(socket, "session_created", event)

      "session.updated" ->
        Logger.info("Session updated: #{inspect(event["session"])}")
        push(socket, "session_updated", event)

      "input_audio_buffer.speech_started" ->
        push(socket, "speech_started", event)

      "input_audio_buffer.speech_stopped" ->
        push(socket, "speech_stopped", event)

      "conversation.item.input_audio_transcription.completed" ->
        push(socket, "transcription_completed", event)

      "response.text.delta" ->
        push(socket, "text_delta", %{"delta" => event["delta"]})

      "response.audio.delta" ->
        push(socket, "audio_delta", %{"delta" => event["delta"]})

      "conversation.item.created" ->
        push(socket, "conversation_item", event)

      "response.function_call_arguments.done" ->
        handle_function_call(event, socket)

      "input_audio_buffer.committed" ->
        push(socket, "audio_committed", event)

      "response.created" ->
        push(socket, "response_created", event)

      "response.output_item.added" ->
        push(socket, "output_item_added", event)

      "response.content_part.added" ->
        push(socket, "content_part_added", event)

      "response.audio_transcript.delta" ->
        push(socket, "audio_transcript_delta", event)

      "response.audio.done" ->
        push(socket, "audio_done", event)

      "response.audio_transcript.done" ->
        push(socket, "audio_transcript_done", event)

      "response.content_part.done" ->
        push(socket, "content_part_done", event)

      "response.output_item.done" ->
        push(socket, "output_item_done", event)

      "response.done" ->
        push(socket, "response_done", event)

      "rate_limits.updated" ->
        push(socket, "rate_limits_updated", event)

      _ ->
        Logger.warn("Realtime Channel Unhandled event type: #{type}")
        push(socket, "api_event", %{type: type, data: event})
    end

    {:noreply, socket}
  end

  defp handle_function_call(event, socket) do
    function_name = event["item"]["name"]
    arguments = Jason.decode!(event["arguments"])

    result = execute_function(function_name, arguments)

    WebSockex.cast(
      socket.assigns.api_client,
      {:send_function_output, event["call_id"], result}
    )

    {:noreply, socket}
  end

  defp execute_function("get_weather", %{"location" => location}) do
    %{"weather" => "Sunny", "temperature" => "25°C in #{location}"}
  end

  defp execute_function("scrape_data", %{"url" => url}) do
    case scrape_url(url) do
      {:ok, data} -> %{"data" => data}
      {:error, reason} -> %{"error" => reason}
    end
  end

  defp scrape_url(url) do
    {:ok, "Scraped data from #{url}: Sample content"}
  end
end
