defmodule Chatgpt.RealtimeApiClient do
  use WebSockex
  require Logger

  @openai_api_url "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-10-01"

  def start_link(opts \\ []) do
    state = %{channel_pid: Keyword.get(opts, :channel_pid)}
    url = @openai_api_url

    api_key =
      System.get_env("OPENAI_API_KEY") || raise "Missing OPENAI_API_KEY environment variable"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"OpenAI-Beta", "realtime=v1"}
    ]

    WebSockex.start_link(url, __MODULE__, state, extra_headers: headers)
  end

  # Handle the WebSocket connection being established
  def handle_connect(_conn, state) do
    Logger.info("Connected to OpenAI Realtime API")
    # Send session.create event after connecting
    send(self(), :send_session_create)
    {:ok, state}
  end

  def handle_connect({:error, reason}, state) do
    Logger.error("Failed to connect to OpenAI Realtime API: #{inspect(reason)}")
    {:close, reason, state}
  end

  def handle_info(:send_session_create, state) do
    event = %{
      type: "response.create",
      response: %{
        modalities: ["text", "audio"],
        instructions:
          "You are an AI assistant named Alex and are designed to conduct onboarding interviews with music artists. Your primary goal is to gather comprehensive information about the artist's career, experience, preferences, and aspirations to create a detailed profile. This profile will be utilized to provide personalized advice and support tailored to their unique needs throughout their musical journey. Go through this list and only ask one question at a time. Start with introducing yourself.",
        voice: "alloy",
        output_audio_format: "pcm16",
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
          },
          %{
            type: "function",
            name: "scrape_data",
            description: "Scrapes data from a given URL.",
            parameters: %{
              type: "object",
              properties: %{
                url: %{type: "string", description: "URL to scrape data from."}
              },
              required: ["url"]
            }
          }
        ],
        tool_choice: "auto",
        temperature: 0.7,
        max_output_tokens: "inf"
      }
    }

    frame = {:text, Jason.encode!(event)}
    {:reply, frame, state}
  end

  # Handle messages from the RealtimeChannel (client input)
  def handle_cast({:send_audio_chunk, base64_audio}, state) do
    event = %{
      type: "input_audio_buffer.append",
      audio: base64_audio
    }

    frame = {:text, Jason.encode!(event)}
    {:reply, frame, state}
  end

  def handle_cast({:send_text_input, text}, state) do
    event = %{
      type: "conversation.item.create",
      item: %{
        type: "message",
        role: "user",
        content: [%{type: "text", text: text}]
      }
    }

    frame = {:text, Jason.encode!(event)}
    {:reply, frame, state}
  end

  def handle_cast(:interrupt, state) do
    event = %{type: "response.cancel"}
    frame = {:text, Jason.encode!(event)}
    {:reply, frame, state}
  end

  # Update the handle_frame function
  def handle_frame({:text, msg}, state) do
    event = Jason.decode!(msg)
    handle_api_event(event, state)
  end

  # Update the handle_api_event function
  defp handle_api_event(%{"type" => event_type} = event, state) do
    case event_type do
      "error" ->
        handle_error_event(event)

      "session.created" ->
        send(state.channel_pid, {:realtime_event, :session_created, event})

      "session.updated" ->
        send(state.channel_pid, {:realtime_event, :session_updated, event})

      "input_audio_buffer.speech_started" ->
        send(state.channel_pid, {:realtime_event, :speech_started, event})

      "input_audio_buffer.speech_stopped" ->
        send(state.channel_pid, {:realtime_event, :speech_stopped, event})

      "input_audio_buffer.committed" ->
        send(state.channel_pid, {:realtime_event, :audio_buffer_committed, event})

      "conversation.item.input_audio_transcription.completed" ->
        send(state.channel_pid, {:realtime_event, :input_audio_transcription_completed, event})

      "conversation.item.created" ->
        send(state.channel_pid, {:realtime_event, :conversation_item_created, event})

      "response.created" ->
        send(state.channel_pid, {:realtime_event, :response_created, event})

      "response.audio_transcript.delta" ->
        send(state.channel_pid, {:realtime_event, :audio_transcript_delta, event})

      "response.audio.delta" ->
        send(state.channel_pid, {:realtime_event, :audio_delta, event})

      "response.audio.done" ->
        send(state.channel_pid, {:realtime_event, :audio_done, event})

      "response.audio_transcript.done" ->
        send(state.channel_pid, {:realtime_event, :audio_transcript_done, event})

      "response.content_part.done" ->
        send(state.channel_pid, {:realtime_event, :content_part_done, event})

      "response.output_item.done" ->
        send(state.channel_pid, {:realtime_event, :output_item_done, event})

      "response.done" ->
        send(state.channel_pid, {:realtime_event, :response_done, event})

      "response.output_item.added" ->
        send(state.channel_pid, {:realtime_event, :output_item_added, event})

      "response.content_part.added" ->
        send(state.channel_pid, {:realtime_event, :content_part_added, event})

      "rate_limits.updated" ->
        send(state.channel_pid, {:realtime_event, :rate_limits_updated, event})

      "response.text.delta" ->
        send(state.channel_pid, {:realtime_event, :text_delta, event})

      "response.function_call" ->
        send(state.channel_pid, {:realtime_event, :function_call, event})

      "response.function_call.arguments.delta" ->
        send(state.channel_pid, {:realtime_event, :function_call_arguments_delta, event})

      "response.function_call.done" ->
        send(state.channel_pid, {:realtime_event, :function_call_done, event})

      _ ->
        Logger.warn("Realtime Client Unhandled API event: #{event_type}")
    end

    {:ok, state}
  end

  defp handle_error_event(event) do
    Logger.error("Received error event from OpenAI Realtime API:")
    Logger.error("  Type: #{event["error"]["type"] || "Unknown"}")
    Logger.error("  Code: #{event["error"]["code"] || "Unknown"}")
    Logger.error("  Message: #{event["error"]["message"] || "No message provided"}")
    Logger.error("  Param: #{event["error"]["param"] || "N/A"}")
    Logger.error("  Event ID: #{event["event_id"] || "N/A"}")
  end

  def handle_disconnect(conn_status_map, state) do
    Logger.warn("Disconnected from OpenAI Realtime API: #{inspect(conn_status_map)}")
    # Optionally attempt to reconnect
    {:reconnect, state}
  end

  # Function to handle sending function output to the API
  def handle_cast({:send_function_output, call_id, output}, state) do
    event = %{
      type: "conversation.item.create",
      item: %{
        type: "function_call_output",
        call_id: call_id,
        output: Jason.encode!(output)
      }
    }

    frame = {:text, Jason.encode!(event)}
    {:reply, frame, state}
  end

  # Add this new function
  def handle_audio_input(pid, base64_audio) do
    WebSockex.cast(pid, {:send_audio_chunk_base64, base64_audio})
  end

  # Add this new handle_cast clause
  def handle_cast({:send_audio_chunk_base64, base64_audio}, state) do
    event = %{
      type: "input_audio_buffer.append",
      audio: base64_audio
    }

    frame = {:text, Jason.encode!(event)}
    {:reply, frame, state}
  end

  # Update this function to send both commit and response.create events
  def handle_cast(:send_audio_commit, state) do
    commit_event = %{type: "input_audio_buffer.commit"}
    response_event = %{type: "response.create"}

    WebSockex.send_frame(self(), {:text, Jason.encode!(commit_event)})
    WebSockex.send_frame(self(), {:text, Jason.encode!(response_event)})

    {:noreply, state}
  end
end
