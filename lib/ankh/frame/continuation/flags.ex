defmodule Ankh.Frame.Continuation.Flags do
  defstruct [end_headers: false]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Continuation.Flags  do
  alias Ankh.Frame.Continuation.Flags

  import Ankh.Frame.Encoder.Utils

  def decode!(struct, <<_::5, eh::1, _::2>>, _) do
    %{struct | end_headers: int_to_bool(eh)}
  end

  def encode!(%Flags{end_headers: eh}, _) do
    <<0::5, bool_to_int(eh)::1, 0::2>>
  end
end
