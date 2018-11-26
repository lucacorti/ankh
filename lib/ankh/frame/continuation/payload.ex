defmodule Ankh.Frame.Continuation.Payload do
  @moduledoc false

  @type t :: %__MODULE__{hbf: binary}
  defstruct hbf: <<>>
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.Continuation.Payload do
  def encode!(%{hbf: hbf}, _), do: [hbf]
  def decode!(payload, data, _), do: %{payload | hbf: data}
end
