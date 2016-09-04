defmodule Ankh do
  use Application

  def start(_type, _args) do
    Ankh.Supervisor.start_link()
  end
end
