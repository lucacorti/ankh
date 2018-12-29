defmodule Ankh.Frame.Continuation.Payload do
  @moduledoc false

  @type t :: %__MODULE__{hbf: binary}
  defstruct hbf: <<>>
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.Continuation.Payload do
  def decode(payload, data, _) when is_binary(data), do: {:ok, %{payload | hbf: data}}
  def decode(_payload, _options), do: {:error, :decode_error}

  def encode(%{hbf: hbf}, _), do: {:ok, [hbf]}
  def encode(_payload, _options), do: {:error, :encode_error}
end
