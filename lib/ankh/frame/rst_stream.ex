defmodule Ankh.Frame.RstStream do
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x3, flags: nil, payload: %Payload{}
end
