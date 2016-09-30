defmodule Ankh.Frame.RstStream do
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x3, flags: nil, payload: Payload
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.RstStream do
  alias Ankh.Frame.RstStream

  def encode!(frame, options), do: RstStream.encode!(frame, options)
  def decode!(frame, binary, options), do: RstStream.decode!(frame, binary, options)
end
