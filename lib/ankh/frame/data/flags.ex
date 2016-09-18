defmodule Ankh.Frame.Data.Flags do
  defstruct [end_stream: false, padded: false]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Data.Flags  do
  alias Ankh.Frame.Data.Flags

  import Ankh.Frame.Encoder.Utils

  def decode!(struct, <<_::4, pa::1, _::2, es::1>>, _) do
    %{struct | end_stream: int_to_bool!(es), padded: int_to_bool!(pa)}
  end

  def encode!(%Flags{end_stream: es, padded: pa}, _) do
    <<0::4, bool_to_int!(pa)::1, 0::2, bool_to_int!(es)::1>>
  end
end
