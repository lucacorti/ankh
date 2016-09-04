defmodule Ankh.Connection.Supervisor do
  use Supervisor

  alias Ankh.Connection

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [worker(Connection, [])]
    |> supervise(strategy: :simple_one_for_one, restart: :transient)
  end
end
