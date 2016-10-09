defmodule Ankh.Frame.Settings.Flags do
  @moduledoc """
  SETTINGS frame flags
  """

  @type t :: %__MODULE__{ack: boolean}
  defstruct [ack: false]
end

defimpl Ankh.Frame.Flags, for: Ankh.Frame.Settings.Flags  do
  import Ankh.Frame.Utils

  def decode!(struct, <<_::7, ack::1>>, _), do: %{struct | ack: int_to_bool!(ack)}
  def encode!(%{ack: ack}, _), do: <<0::7, bool_to_int!(ack)::1>>
end
