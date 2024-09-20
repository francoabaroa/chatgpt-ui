defmodule Chatgpt.OpenAI2 do
  @behaviour Chatgpt.LLM

  @spec convert_message(Chatgpt.Message.t()) ::
          ExOpenAI.Components.ChatCompletionRequestUserMessage.t()
          | ExOpenAI.Components.ChatCompletionRequestAssistantMessage.t()
  def convert_message(%Chatgpt.Message{sender: :user} = msg) do
    %ExOpenAI.Components.ChatCompletionRequestUserMessage{
      content: msg.content,
      role: :user
    }
  end

  def convert_message(%Chatgpt.Message{sender: :assistant} = msg) do
    %ExOpenAI.Components.ChatCompletionRequestAssistantMessage{
      content: msg.content,
      role: :assistant
    }
  end

  def convert_message(%Chatgpt.Message{sender: :system} = msg) do
    %ExOpenAI.Components.ChatCompletionRequestAssistantMessage{
      content: msg.content,
      role: :system
    }
  end

  @spec do_complete([Chatgpt.Messages], String.t(), Chatgpt.LLM.chunk()) ::
          :ok | {:error, String.t()}
  def do_complete(messages, model, callback) do
    callback = fn
      :finish ->
        IO.puts("Done")
        callback.(:finish)

      {:data, %ExOpenAI.Components.CreateChatCompletionResponse{choices: choices}} ->
        chunk_text =
          choices
          |> List.first()
          |> Map.get(:delta)
          |> Map.get(:content)
          |> escape_backticks()

        callback.({:data, chunk_text})

      {:data, data} when is_map(data) ->
        chunk_text =
          data
          |> get_in([:choices, Access.at(0), :delta, :content])
          |> escape_backticks()

        if chunk_text, do: callback.({:data, chunk_text})

      {:error, err} ->
        IO.puts("Error: #{inspect(err)}")
        callback.({:error, err})
    end

    converted_msgs = Enum.map(messages, &convert_message/1)

    case ExOpenAI.Chat.create_chat_completion(converted_msgs, model,
           temperature: 0.8,
           stream: true,
           stream_to: callback
         ) do
      {:ok, reference} ->
        {:ok, reference}

      {:error, err} ->
        IO.puts("Error: #{inspect(err)}")
        {:error, err}
    end

    :ok
  end

  defp escape_backticks(nil), do: nil

  defp escape_backticks(text) when is_binary(text) do
    String.replace(text, "`", "\\`")
  end
end
