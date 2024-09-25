defmodule Chatgpt.Ets.SessionIdManager do
  use GenServer

  @table_name :session_data

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    {:ok, %{}}
  end

  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  def put(key, value) do
    :ets.insert(@table_name, {key, value})
    :ok
  end

  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end
end
