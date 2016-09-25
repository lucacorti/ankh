defmodule Ankh.Frame.PushPromise.Flags do
  @moduledoc """
  PUSH_PROMISE frame flags
  """

  @type t :: %__MODULE__{end_headers: boolean, padded: boolean}
  defstruct [end_headers: false, padded: false]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.PushPromise.Flags  do
  alias Ankh.Frame.PushPromise.Flags

  import Ankh.Frame.Encoder.Utils

  def decode!(struct, <<_::4, pa::1, eh::1, _::2>>, _) do
    %{struct | end_headers: int_to_bool!(eh), padded: int_to_bool!(pa)}
  end

  def encode!(%Flags{end_headers: eh, padded: pa}, _) do
    <<0::4, bool_to_int!(pa)::1, bool_to_int!(eh)::1, 0::2>>
  end
end
