defmodule Ankh.Frame.WindowUpdate do
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x8, flags: nil, payload: %Payload{}
end
