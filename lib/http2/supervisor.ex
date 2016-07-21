defmodule Http2.Supervisor do
  use Supervisor

  alias Http2.{Client, Connection}

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [
      worker(Client.Supervisor, []),
      worker(Client.Registry, []),
      worker(Connection.Supervisor, []),
      worker(Connection.Registry, [])
    ]
    |> supervise(strategy: :one_for_one)
  end
end
