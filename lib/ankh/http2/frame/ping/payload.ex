defmodule Ankh.HTTP2.Frame.Ping.Payload do
  @moduledoc false

  @type t :: %__MODULE__{data: binary}
  defstruct data: <<>>
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Ping.Payload do
  def decode(payload, data, _) when is_binary(data), do: {:ok, %{payload | data: data}}
  def decode(_payload, _data, _options), do: {:error, :decode_error}

  def encode(%{data: data}, _) when is_binary(data), do: {:ok, [data]}
  def encode(_payload, _options), do: {:error, :encode_error}
end
