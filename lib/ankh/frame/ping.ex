defmodule Ankh.Frame.Ping do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x6, flags: %Flags{}, payload: %Payload{}
end
