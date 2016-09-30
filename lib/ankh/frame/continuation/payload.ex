defmodule Ankh.Frame.Continuation.Payload do
  @moduledoc """
  CONTINUATION frame payload
  """

  @type t :: %__MODULE__{header_block_fragment: binary}
  defstruct [header_block_fragment: <<>>]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Continuation.Payload do
  def encode!(%{header_block_fragment: hbf}, _), do: hbf
  def decode!(struct, data, _), do: %{struct| header_block_fragment: data}
end
