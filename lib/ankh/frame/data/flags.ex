defmodule Ankh.Frame.Data.Flags do
  @moduledoc false

  @type t :: %__MODULE__{end_stream: boolean, padded: boolean}
  defstruct end_stream: false, padded: false
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.Data.Flags do
  def decode(flags, <<_::4, 0::1, _::2, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, padded: false}}
  end

  def decode(flags, <<_::4, 0::1, _::2, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, padded: false}}
  end

  def decode(flags, <<_::4, 1::1, _::2, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, padded: true}}
  end

  def decode(flags, <<_::4, 1::1, _::2, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, padded: true}}
  end

  def decode(_flags, _data, _options), do: {:error, :decode_error}

  def encode(%{end_stream: false, padded: false}, _) do
    {:ok, <<0::4, 0::1, 0::2, 0::1>>}
  end

  def encode(%{end_stream: true, padded: false}, _) do
    {:ok, <<0::4, 0::1, 0::2, 1::1>>}
  end

  def encode(%{end_stream: false, padded: true}, _) do
    {:ok, <<0::4, 1::1, 0::2, 0::1>>}
  end

  def encode(%{end_stream: true, padded: true}, _) do
    {:ok, <<0::4, 1::1, 0::2, 1::1>>}
  end

  def encode(_flags, _options), do: {:error, :encode_error}
end
