defmodule Ankh.HTTP2.Frame.Continuation.Flags do
  @moduledoc false

  @type t :: %__MODULE__{end_headers: boolean}
  defstruct end_headers: false
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Continuation.Flags do
  def decode(flags, <<_::5, 0::1, _::2>>, _) do
    {:ok, %{flags | end_headers: false}}
  end

  def decode(flags, <<_::5, 1::1, _::2>>, _) do
    {:ok, %{flags | end_headers: true}}
  end

  def decode(_flags, _data, _options), do: {:error, :decode_error}

  def encode(%{end_headers: true}, _) do
    {:ok, <<0::5, 1::1, 0::2>>}
  end

  def encode(%{end_headers: false}, _) do
    {:ok, <<0::5, 0::1, 0::2>>}
  end

  def encode(_flags, _options), do: {:error, :encode_error}
end
