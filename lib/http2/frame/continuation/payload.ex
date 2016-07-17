defmodule Http2.Frame.Continuation.Payload do
  defstruct [header_block_fragment: nil]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.Continuation.Payload do
  alias Http2.Frame.Continuation.Payload

  def encode!(%Payload{header_block_fragment: hbf}, _), do: hbf

  def decode!(struct, data, _), do: %{struct| header_block_fragment: data}
end
