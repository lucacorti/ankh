defmodule Ankh.Frame.Ping.Flags do
  @moduledoc false

  @type t :: %__MODULE__{ack: boolean}
  defstruct ack: false
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.Ping.Flags do
  import Ankh.Frame.Utils

  def decode!(flags, <<_::7, ack::1>>, _), do: %{flags | ack: int_to_bool!(ack)}
  def encode!(%{ack: ack}, _), do: <<0::7, bool_to_int!(ack)::1>>
end
