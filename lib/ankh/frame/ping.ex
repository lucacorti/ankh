defmodule Ankh.Frame.Ping do
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x6, flags: Flags, payload: Payload
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Ping do
  alias Ankh.Frame.Ping

  def encode!(frame, options), do: Ping.encode!(frame, options)
  def decode!(frame, binary, options), do: Ping.decode!(frame, binary, options)
end
