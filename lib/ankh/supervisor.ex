defmodule Ankh.Supervisor do
  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    [
      {Registry, keys: :unique, name: Ankh.HTTP2.Frame.Registry}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
