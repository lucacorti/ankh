defmodule Ankh.Frame.Continuation do
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x9, flags: %Flags{}, payload: %Payload{}
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Continuation do
  alias Ankh.Frame.Continuation

  def encode!(frame, options), do: Continuation.encode!(frame, options)
  def decode!(frame, binary, options), do: Continuation.decode!(frame, binary, options)
end
