defmodule Http2.Frame.Data.Flags do
  defstruct [end_stream: false, padded: false]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.Data.Flags  do
  alias Http2.Frame.Data.Flags

  import Http2.Frame.Encoder.Utils

  def decode!(struct, <<_::4, pa::1, _::2, es::1>>, _) do
    %{struct | end_stream: int_to_bool(es), padded: int_to_bool(pa)}
  end

  def encode!(%Flags{end_stream: es, padded: pa}, _) do
    <<0::4, bool_to_int(pa)::1, 0::2, bool_to_int(es)::1>>
  end
end
