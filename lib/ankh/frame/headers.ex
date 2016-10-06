defmodule Ankh.Frame.Headers do
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x1, flags: %Flags{}, payload: %Payload{}
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Headers do
  alias Ankh.Frame.Headers

  def encode!(frame, options), do: Headers.encode!(frame, options)
  def decode!(frame, binary, options), do: Headers.decode!(frame, binary, options)
end
