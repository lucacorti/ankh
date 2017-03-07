defmodule Ankh.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [supervisor(Connection.Supervisor, [])]
    |> supervise(strategy: :simple_one_for_one, restart: :transient)
  end
end
