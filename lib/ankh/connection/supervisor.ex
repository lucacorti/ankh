defmodule Ankh.Connection.Supervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    [worker(Connection, args), worker(Receiver, args)]
    |> supervise(strategy: :one_for_all, restart: :transient)
  end
end
