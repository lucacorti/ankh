defmodule Ankh.Frame.PushPromise do
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x5, flags: Flags, payload: Payload
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.PushPromise do
  alias Ankh.Frame.PushPromise

  def encode!(frame, options), do: PushPromise.encode!(frame, options)
  def decode!(frame, binary, options), do: PushPromise.decode!(frame, binary, options)
end
