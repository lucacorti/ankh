defmodule Ankh.Frame.WindowUpdate do
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x8, flags: nil, payload: Payload
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.WindowUpdate do
  alias Ankh.Frame.WindowUpdate

  def encode!(frame, options), do: WindowUpdate.encode!(frame, options)
  def decode!(frame, binary, options), do: WindowUpdate.decode!(frame, binary, options)
end
