defmodule Http2 do
  use Application

  def start(_type, _args) do
    Http2.Supervisor.start_link()
  end
end
