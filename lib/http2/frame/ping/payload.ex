defmodule Http2.Frame.Ping.Payload do
  defstruct [data: nil]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.Ping.Payload do
  alias Http2.Frame.Ping.Payload

  def encode!(%Payload{data: data}, _) when is_binary(data), do: data

  def decode!(struct, data, _) when is_binary(data), do: %{struct | data: data}
end
