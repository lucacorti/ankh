defmodule Ankh.Frame.Continuation.Payload do
  @moduledoc """
  CONTINUATION frame payload
  """

  @type t :: %__MODULE__{hbf: binary}
  defstruct [hbf: <<>>]
end

defimpl Ankh.Frame.Payload, for: Ankh.Frame.Continuation.Payload do
  def encode!(%{hbf: hbf}, _), do: [hbf]
  def decode!(struct, data, _), do: %{struct| hbf: data}
end
