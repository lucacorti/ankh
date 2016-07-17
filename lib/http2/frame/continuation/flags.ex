defmodule Http2.Frame.Continuation.Flags do
  defstruct [end_headers: false]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.Continuation.Flags  do
  alias Http2.Frame.Continuation.Flags

  import Http2.Frame.Encoder.Utils

  def decode!(struct, <<_::5, eh::1, _::2>>, _) do
    %{struct | end_headers: int_to_bool(eh)}
  end

  def encode!(%Flags{end_headers: eh}, _) do
    <<0::5, bool_to_int(eh)::1, 0::2>>
  end
end
