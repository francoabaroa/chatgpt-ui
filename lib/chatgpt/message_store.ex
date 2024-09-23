defmodule Chatgpt.MessageStore do
  use Agent
  require Logger

  @spec start_link([Chatgpt.Message.t()]) :: {:ok, pid} | {:error, any()}
  def start_link(initial_messages \\ []) do
    # add id to each message
    initial_messages =
      Enum.with_index(initial_messages, 1)
      |> Enum.map(fn {msg, i} -> Map.put(msg, :id, i) end)

    queue = :queue.from_list(initial_messages)
    Agent.start_link(fn -> queue end)
  end

  @spec add_message(pid, %Chatgpt.Message{}) :: :ok
  def add_message(pid, message) do
    Agent.update(pid, fn queue ->
      next_id = :queue.len(queue) + 1
      message_with_id = Map.put(message, :id, next_id)
      :queue.in(message_with_id, queue)
    end)
  end

  @spec get_messages(pid) :: [%Chatgpt.Message{}]
  def get_messages(pid) do
    Agent.get(pid, fn queue -> :queue.to_list(queue) end)
  end

  def get_recent_messages(pid, x) do
    Agent.get(pid, fn queue ->
      queue
      |> :queue.to_list()
      |> Enum.take(-x)
    end)
  end

  @spec get_next_id(pid) :: integer()
  def get_next_id(pid) do
    Agent.get(pid, fn queue -> :queue.len(queue) end) + 1
  end
end
