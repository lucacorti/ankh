defmodule Ankh.Frame.Continuation.Flags do
  @moduledoc false

  @type t :: %__MODULE__{end_headers: boolean}
  defstruct end_headers: false
end

defimpl Ankh.Frame.Flags, for: Ankh.Frame.Continuation.Flags do
  import Ankh.Frame.Utils

  def decode!(struct, <<_::5, eh::1, _::2>>, _) do
    %{struct | end_headers: int_to_bool!(eh)}
  end

  def encode!(%{end_headers: eh}, _) do
    <<0::5, bool_to_int!(eh)::1, 0::2>>
  end
end
