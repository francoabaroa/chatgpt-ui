defmodule Chatgpt.Tokenizer do
  defmodule State do
    defstruct tokenizer: nil
  end

  use GenServer
  require Logger

  @model "bert-base-multilingual-uncased"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    {:ok, %State{tokenizer: nil}}
  end

  def handle_call({:count_tokens, input}, _from, state) do
    case ensure_tokenizer_loaded(state) do
      {:ok, tokenizer, new_state} ->
        case Tokenizers.Tokenizer.encode(
               tokenizer,
               input,
               add_special_tokens: false
             ) do
          {:ok, encoding} ->
            token_count = Tokenizers.Encoding.get_tokens(encoding) |> Enum.count()
            {:reply, {:ok, token_count}, new_state}

          {:error, e} ->
            {:reply, {:error, e}, new_state}
        end

      {:error, e, state} ->
        {:reply, {:error, e}, state}
    end
  end

  defp ensure_tokenizer_loaded(%State{tokenizer: nil} = state) do
    Logger.info("Loading tokenizer model: #{@model}")

    cache_dir = System.get_env("TOKENIZER_CACHE_DIR") || "/tmp/.cache/tokenizers_elixir"
    File.mkdir_p!(cache_dir)

    case Tokenizers.Tokenizer.from_pretrained(@model, cache_dir: cache_dir) do
      {:ok, tokenizer} ->
        {:ok, tokenizer, %{state | tokenizer: tokenizer}}

      {:error, e} ->
        {:error, e, state}
    end
  end

  defp ensure_tokenizer_loaded(%State{tokenizer: tokenizer} = state), do: {:ok, tokenizer, state}

  def count_tokens(input) do
    GenServer.call(__MODULE__, {:count_tokens, input})
  end

  def count_tokens!(input) do
    {:ok, tokens} = GenServer.call(__MODULE__, {:count_tokens, input})
    tokens
  end
end
