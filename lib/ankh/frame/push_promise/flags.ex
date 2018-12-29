defmodule Ankh.Frame.PushPromise.Flags do
  @moduledoc false

  @type t :: %__MODULE__{end_headers: boolean, padded: boolean}
  defstruct end_headers: false, padded: false
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.PushPromise.Flags do
  def decode(flags, <<_::4, 1::1, 1::1, _::2>>, _) do
    {:ok, %{flags | end_headers: true, padded: true}}
  end

  def decode(flags, <<_::4, 1::1, 0::1, _::2>>, _) do
    {:ok, %{flags | end_headers: false, padded: true}}
  end

  def decode(flags, <<_::4, 0::1, 1::1, _::2>>, _) do
    {:ok, %{flags | end_headers: true, padded: false}}
  end

  def decode(flags, <<_::4, 0::1, 0::1, _::2>>, _) do
    {:ok, %{flags | end_headers: false, padded: false}}
  end

  def decode(_flags, _data, _options), do: {:error, :decode_error}

  def encode(%{end_headers: true, padded: true}, _) do
    {:ok, <<0::4, 1::1, 1::1, 0::2>>}
  end

  def encode(%{end_headers: true, padded: false}, _) do
    {:ok, <<0::4, 0::1, 1::1, 0::2>>}
  end

  def encode(%{end_headers: false, padded: true}, _) do
    {:ok, <<0::4, 1::1, 0::1, 0::2>>}
  end

  def encode(%{end_headers: false, padded: false}, _) do
    {:ok, <<0::4, 0::1, 0::1, 0::2>>}
  end

  def encode(_flags, _options), do: {:error, :encode_error}
end
