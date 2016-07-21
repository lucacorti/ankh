defmodule Http2.Connection.Supervisor do
  use Supervisor

  alias Http2.Connection

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [worker(Connection, [])]
    |> supervise(strategy: :simple_one_for_one)
  end

  def get_connection(uri) do
    case Connection.Registry.whereis_name(uri) do
      :undefined ->
        options = [name: {:via, Connection.Registry, uri}]
        Supervisor.start_child(__MODULE__, [uri, options])
      pid ->
        {:ok, pid}
    end
  end
end
