defmodule Http2.Frame.PushPromise.Flags do
  defstruct [end_headers: false, padded: false]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.PushPromise.Flags  do
  alias Http2.Frame.PushPromise.Flags

  import Http2.Frame.Encoder.Utils

  def decode!(struct, <<_::4, pa::1, eh::1, _::2>>, _) do
    %{struct | end_headers: int_to_bool(eh), padded: int_to_bool(pa)}
  end

  def encode!(%Flags{end_headers: eh, padded: pa}, _) do
    <<0::4, bool_to_int(pa)::1, bool_to_int(eh)::1, 0::2>>
  end
end
