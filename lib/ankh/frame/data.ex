defmodule Ankh.Frame.Data do
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x0, flags: %Flags{}, payload: %Payload{}
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Data do
  alias Ankh.Frame.Data

  def encode!(frame, options), do: Data.encode!(frame, options)
  def decode!(frame, binary, options), do: Data.decode!(frame, binary, options)
end
