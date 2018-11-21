defmodule Ankh.Frame.Data.Flags do
  @moduledoc false

  @type t :: %__MODULE__{end_stream: boolean, padded: boolean}
  defstruct end_stream: false, padded: false
end

defimpl Ankh.Frame.Flags, for: Ankh.Frame.Data.Flags do
  import Ankh.Frame.Utils

  def decode!(flags, <<_::4, pa::1, _::2, es::1>>, _) do
    %{flags | end_stream: int_to_bool!(es), padded: int_to_bool!(pa)}
  end

  def encode!(%{end_stream: es, padded: pa}, _) do
    <<0::4, bool_to_int!(pa)::1, 0::2, bool_to_int!(es)::1>>
  end
end
