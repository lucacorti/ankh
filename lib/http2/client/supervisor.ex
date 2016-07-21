defmodule Http2.Client.Supervisor do
  use Supervisor

  alias Http2.Client

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [worker(Client, [])]
    |> supervise(strategy: :simple_one_for_one)
  end

  def get_client(uri) do
    case Client.Registry.whereis_name(uri) do
      :undefined ->
        options = [name: {:via, Client.Registry, uri}]
        Supervisor.start_child(__MODULE__, [uri, options])
      pid ->
        {:ok, pid}
    end
  end
end
