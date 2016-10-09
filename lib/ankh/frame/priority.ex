defmodule Ankh.Frame.Priority do
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x5, flags: nil, payload: %Payload{}
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Priority do
  alias Ankh.Frame.Encoder

  def encode!(frame, options), do: Encoder.encode!(frame, options)
  def decode!(frame, binary, options), do: Encoder.decode!(frame, binary, options)
end
