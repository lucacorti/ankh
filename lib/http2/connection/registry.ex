defmodule Http2.Connection.Registry do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_), do: {:ok, %{}}

  def whereis_name(name) do
    GenServer.call(__MODULE__, {:whereis_name, name})
  end

  def register_name(name, pid) do
    GenServer.call(__MODULE__, {:register_name, name, pid})
  end

  def unregister_name(name) do
    GenServer.cast(__MODULE__, {:unregister_name, name})
  end

  def handle_call({:whereis_name, name}, _from, state) do
    {:reply, Map.get(state, name, :undefined), state}
  end

  def handle_call({:register_name, name, pid}, _from, state) do
    case Map.get(state, name) do
      nil ->
        Process.monitor(pid)
        {:reply, :yes, Map.put(state, name, pid)}
      _ ->
        {:reply, :no, state}
    end
  end

  def handle_cast({:unregister_name, name}, state) do
   {:noreply, Map.delete(state, name)}
  end

  def handle_info({:DOWN, _, :process, pid, _}, state) do
    {:noreply, remove_pid(state, pid)}
  end

  defp remove_pid(state, pid_to_remove) do
    state
    |> Enum.filter(fn {_key, pid} -> pid  != pid_to_remove end)
    |> Enum.into(%{})
  end
end
