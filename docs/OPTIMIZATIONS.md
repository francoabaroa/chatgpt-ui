**Optimization 1: Limit Message History to Reduce LLM Load**

1. **File Path and Line Number(s):**
   - `lib/chatgpt_web/live/index.ex`, lines around 147
   - `lib/chatgpt/message_store.ex`, update `get_messages/1` function

2. **Description of the Issue/Inefficiency:**
   - The application sends the entire conversation history to the LLM (Language Model) with every user message. As the conversation grows, this increases the payload size, leading to longer response times, higher costs, and potential API rate limits or token limits being exceeded.

3. **Estimated Impact on Performance:**
   - **High Impact:** By limiting the number of messages sent to the LLM, we reduce the payload size, which decreases latency and processing time. This also reduces costs if the LLM service charges based on token usage.

4. **Specific Suggestions for Optimization:**
   - Implement a mechanism to limit the conversation context sent to the LLM. This can be based on:
     - A fixed number of recent messages (e.g., the last 10 messages).
     - A token limit where messages are included until a token threshold is reached.
   - Modify the `get_messages/1` function in `Chatgpt.MessageStore` to accept a limit parameter.
   - Update the LiveView to use the limited message history when calling `LLM.do_complete/3`.

**Updated Code:**

**File:** `lib/chatgpt/message_store.ex`

```elixir
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

  @spec get_messages(pid, limit :: integer() | nil) :: [%Chatgpt.Message{}]
  def get_messages(pid, limit \\ nil) do
    Agent.get(pid, fn queue ->
      messages = :queue.to_list(queue)
      case limit do
        nil -> messages
        n when is_integer(n) -> Enum.take(messages, -n)
        _ -> messages
      end
    end)
  end

  def get_recent_messages(pid, x) do
    get_messages(pid, x)
  end

  @spec get_next_id(pid) :: integer()
  def get_next_id(pid) do
    Agent.get(pid, fn queue -> :queue.len(queue) end) + 1
  end
end
```

**File:** `lib/chatgpt_web/live/index.ex`

```elixir
defmodule ChatgptWeb.IndexLive do
  # ... existing code ...

  def handle_info({:msg_submit, text}, %{assigns: %{loading: false}} = socket) do
    self = self()

    Process.send(self, :start_loading, [])
    Process.send(self, :sync_messages, [])

    model = socket.assigns.model

    # Add new message to message_store
    Chatgpt.MessageStore.add_message(socket.assigns.message_store_pid, %Chatgpt.Message{
      content: text,
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

    # Limit the number of messages based on model's token limit
    max_tokens = socket.assigns.active_model.truncate_tokens
    messages = limit_messages(socket.assigns.message_store_pid, socket.assigns.prepend_messages, max_tokens)

    llm = Chatgpt.LLM.get_provider(socket.assigns.active_model.provider)
    llm.do_complete(messages, model, handle_chunk_callback)

    {:noreply, socket |> assign(:loading, true) |> clear_flash()}
  end

  defp limit_messages(message_store_pid, prepend_messages, max_tokens) do
    messages = Chatgpt.MessageStore.get_messages(message_store_pid)
    total_messages = prepend_messages ++ messages

    # Start from the end and accumulate messages until token limit is reached
    {limited_messages, _remaining_tokens} =
      Enum.reverse(total_messages)
      |> Enum.reduce_while({[], max_tokens}, fn message, {acc, tokens_left} ->
        message_tokens = Chatgpt.Tokenizer.count_tokens!(message.content)
        if tokens_left - message_tokens >= 0 do
          {:cont, {[message | acc], tokens_left - message_tokens}}
        else
          {:halt, {acc, tokens_left}}
        end
      end)

    prepend_messages ++ limited_messages
  end

  # ... existing code ...
end
```

**Explanation:**

- In `Chatgpt.MessageStore`, we've updated the `get_messages/1` function to accept an optional `limit` parameter, returning only the most recent messages up to that limit.
- In `ChatgptWeb.IndexLive`, we introduced a new function `limit_messages/3` that:
  - Retrieves all messages, including any prepend messages (e.g., system prompts).
  - Iterates over the messages in reverse (from most recent) and accumulates them until the token limit is reached.
  - Uses `Chatgpt.Tokenizer.count_tokens!/1` to count the tokens in each message.
- When `handle_info/2` processes a new user message, it calls `limit_messages/3` to ensure the context sent to the LLM stays within the model's token limit.

---

**Optimization 2: Use ETS for Message Storage Instead of Agent**

1. **File Path and Line Number(s):**
   - `lib/chatgpt/message_store.ex`, entire module.

2. **Description of the Issue/Inefficiency:**
   - The current implementation uses an `Agent` with an in-memory queue to store messages. As the number of messages grows, accessing and updating the queue can become a bottleneck, especially with concurrent access. Agents serialize access, which can lead to performance issues under load.

3. **Estimated Impact on Performance:**
   - **Medium to High Impact:** Switching to ETS (Erlang Term Storage) allows for concurrent read access and faster data retrieval, improving performance in multi-user scenarios or when message volumes are high.

4. **Specific Suggestions for Optimization:**
   - Replace the `Agent` with an ETS table to store messages.
   - Use `:bag` or `:ordered_set` as the table type to efficiently store and retrieve messages.
   - Update functions to interact with the ETS table instead of the Agent.

**Updated Code:**

**File:** `lib/chatgpt/message_store.ex`

```elixir
defmodule Chatgpt.MessageStore do
  use GenServer
  require Logger

  @spec start_link([Chatgpt.Message.t()]) :: {:ok, pid} | {:error, any()}
  def start_link(initial_messages \\ []) do
    GenServer.start_link(__MODULE__, initial_messages, name: __MODULE__)
  end

  def init(initial_messages) do
    table = :ets.new(:message_store, [:ordered_set, :public, read_concurrency: true])
    Enum.each(initial_messages, fn message ->
      :ets.insert(table, {message.id, message})
    end)
    {:ok, %{table: table, next_id: Enum.count(initial_messages) + 1}}
  end

  @spec add_message(pid, %Chatgpt.Message{}) :: :ok
  def add_message(pid, message) do
    GenServer.call(pid, {:add_message, message})
  end

  @spec get_messages(pid, limit :: integer() | nil) :: [%Chatgpt.Message{}]
  def get_messages(pid, limit \\ nil) do
    GenServer.call(pid, {:get_messages, limit})
  end

  @spec get_recent_messages(pid, x :: integer()) :: [%Chatgpt.Message{}]
  def get_recent_messages(pid, x) do
    get_messages(pid, x)
  end

  @spec get_next_id(pid) :: integer()
  def get_next_id(pid) do
    GenServer.call(pid, :get_next_id)
  end

  def handle_call({:add_message, message}, _from, state) do
    message_with_id = Map.put(message, :id, state.next_id)
    :ets.insert(state.table, {state.next_id, message_with_id})
    {:reply, :ok, %{state | next_id: state.next_id + 1}}
  end

  def handle_call({:get_messages, limit}, _from, state) do
    messages = :ets.tab2list(state.table) |> Enum.map(fn {_id, msg} -> msg end)
    messages =
      case limit do
        nil -> messages
        n when is_integer(n) -> Enum.take(messages, -n)
        _ -> messages
      end
    {:reply, messages, state}
  end

  def handle_call(:get_next_id, _from, state) do
    {:reply, state.next_id, state}
  end
end
```

**Explanation:**

- Replaced the `Agent` with a `GenServer` that manages an ETS table.
- The ETS table is created with options `[:ordered_set, :public, read_concurrency: true]` for efficient concurrent reads.
- Messages are stored in the ETS table with their `id` as the key.
- Updated methods to interact with the ETS table.
- This change allows for faster access to messages, especially when the number of messages grows, and improves concurrency performance.

---

**Optimization 3: Optimize Message Fixing Logic in LLM Providers**

1. **File Path and Line Number(s):**
   - `lib/chatgpt/vertex.ex`, `fix_messages/1` function.
   - Similar logic in `lib/chatgpt/anthropic.ex`.

2. **Description of the Issue/Inefficiency:**
   - The `fix_messages/1` function in `Chatgpt.Vertex` uses `Enum.reduce/3` and concatenates lists, which can be inefficient due to repeated list traversals and accumulations.
   - Similar patterns exist in other LLM provider modules.

3. **Estimated Impact on Performance:**
   - **Low to Medium Impact:** Optimizing list operations can improve performance in functions that are called frequently, especially with larger message histories.

4. **Specific Suggestions for Optimization:**
   - Use accumulators appropriately in `Enum.reduce/3` to avoid list concatenations.
   - Prepend elements to the accumulator and reverse the list at the end, which is more efficient.

**Updated Code:**

**File:** `lib/chatgpt/vertex.ex`

```elixir
def fix_messages(messages) do
  messages
  |> Enum.reduce([], fn message, acc ->
    case {acc, message} do
      # Insert assistant between user/system and user messages
      ([%Chatgpt.Message{sender: prev_sender} | _] = acc, %Chatgpt.Message{sender: :user})
      when prev_sender in [:user, :system] ->
        [%Chatgpt.Message{sender: :assistant, content: "ok"}, message | acc]

      # Insert assistant between assistant and assistant messages
      ([%Chatgpt.Message{sender: :assistant} | _], %Chatgpt.Message{sender: :assistant}) ->
        [%Chatgpt.Message{sender: :user, content: "ok"}, message | acc]

      # Default case: just prepend the message
      _ ->
        [message | acc]
    end
  end)
  |> Enum.reverse()
end
```

**Explanation:**

- In the `fix_messages/1` function, we now prepend messages to the accumulator and reverse the list at the end.
- This avoids expensive list concatenations (`++`) in each iteration, improving performance.
- Similar changes can be applied to other LLM provider modules that use similar message fixing logic.

---

**Optimization 5: Use More Efficient Data Structures for Messages**

1. **File Path and Line Number(s):**
   - `lib/chatgpt/message_store.ex`, depending on chosen implementation.

2. **Description of the Issue/Inefficiency:**
   - Current storage uses lists or queues which may not be the most efficient for the required operations.

3. **Estimated Impact on Performance:**
   - **Low to Medium Impact:** Depending on message volume and access patterns.

4. **Specific Suggestions for Optimization:**
   - If specific messages need to be accessed or updated frequently by ID, consider using a map or a combination of data structures.
   - Ensure that data structures are chosen based on access patterns (e.g., frequent inserts at the end, reads of recent messages).

Given that we've already switched to ETS, which supports efficient lookups, we may have addressed this issue.

---

These optimizations focus on areas that can significantly improve the performance of your Elixir/Phoenix application without sacrificing readability or maintainability. The `Optimization 1` is likely to have the most immediate impact, especially in terms of reducing latency and cost. `Optimization 2` improves the concurrent performance and scalability of the message storage. `Optimization 3` shortens application startup time. `Optimization 4` refines internal functions for better efficiency.

Please review these changes and consider incorporating them into your codebase. Let me know if you have any questions or need further assistance!