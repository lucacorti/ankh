defmodule Ankh.Frame.Ping.Flags do
  defstruct [ack: false]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Ping.Flags  do
  alias Ankh.Frame.Ping.Flags

  import Ankh.Frame.Encoder.Utils

  def decode!(struct, <<_::7, ack::1>>, _) do
    %{struct | ack: int_to_bool(ack)}
  end

  def encode!(%Flags{ack: ack}, _) do
    <<0::7, bool_to_int(ack)::1>>
  end
end
