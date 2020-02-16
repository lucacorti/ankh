defmodule Ankh.HTTP2.Frame.Ping.Flags do
  @moduledoc false

  @type t :: %__MODULE__{ack: boolean}
  defstruct ack: false
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Ping.Flags do
  def decode(flags, <<_::7, 1::1>>, _), do: {:ok, %{flags | ack: true}}
  def decode(flags, <<_::7, 0::1>>, _), do: {:ok, %{flags | ack: false}}
  def decode(_flags, _data, _options), do: {:error, :decode_error}

  def encode(%{ack: true}, _), do: {:ok, <<0::7, 1::1>>}
  def encode(%{ack: false}, _), do: {:ok, <<0::7, 0::1>>}
  def encode(_flags, _options), do: {:error, :encode_error}
end
