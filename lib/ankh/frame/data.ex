defmodule Ankh.Frame.Data do
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x0, flags: %Flags{}, payload: %Payload{}
end
