defmodule Ankh.Frame.Settings do
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x4, flags: Flags, payload: Payload
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Settings do
  alias Ankh.Frame.Settings

  def encode!(frame, options), do: Settings.encode!(frame, options)
  def decode!(frame, binary, options), do: Settings.decode!(frame, binary, options)
end
