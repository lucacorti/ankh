defmodule Ankh.Frame.Priority do
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x5, flags: nil, payload: Payload
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Priority do
  alias Ankh.Frame.Priority

  def encode!(frame, options), do: Priority.encode!(frame, options)
  def decode!(frame, binary, options), do: Priority.decode!(frame, binary, options)
end
