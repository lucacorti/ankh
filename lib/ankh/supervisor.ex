defmodule Ankh.Supervisor do
  @moduledoc """
  Ankh Supervisor
  """
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [supervisor(Registry, [:unique, Ankh.Frame.Registry], id: Ankh.Frame.Registry)]
    |> supervise(strategy: :one_for_one)
  end
end
