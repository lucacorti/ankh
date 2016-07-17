defmodule Http2.Frame.Ping.Flags do
  defstruct [ack: false]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.Ping.Flags  do
  alias Http2.Frame.Ping.Flags

  import Http2.Frame.Encoder.Utils

  def decode!(struct, <<_::7, ack::1>>, _) do
    %{struct | ack: int_to_bool(ack)}
  end

  def encode!(%Flags{ack: ack}, _) do
    <<0::7, bool_to_int(ack)::1>>
  end
end
