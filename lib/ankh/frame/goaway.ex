defmodule Ankh.Frame.Goaway do
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x7, flags: nil, payload: Payload
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Goaway do
  alias Ankh.Frame.Goaway

  def encode!(frame, options), do: Goaway.encode!(frame, options)
  def decode!(frame, binary, options), do: Goaway.decode!(frame, binary, options)
end
