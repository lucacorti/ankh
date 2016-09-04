defmodule Ankh.Client.Supervisor do
  use Supervisor

  alias Ankh.Client

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [worker(Client, [])]
    |> supervise(strategy: :simple_one_for_one, restart: :transient)
  end
end
