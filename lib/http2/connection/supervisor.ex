defmodule Http2.Connection.Supervisor do
  use Supervisor

  alias Http2.Connection

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [worker(Connection, [])]
    |> supervise(strategy: :simple_one_for_one, restart: :transient)
  end
end
