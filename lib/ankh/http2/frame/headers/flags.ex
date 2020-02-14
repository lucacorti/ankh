defmodule Ankh.HTTP2.Frame.Headers.Flags do
  @moduledoc false

  @type t :: %__MODULE__{
          end_stream: boolean,
          end_headers: boolean,
          padded: boolean,
          priority: boolean
        }
  defstruct end_stream: false, end_headers: false, padded: false, priority: false
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Headers.Flags do
  def decode(flags, <<_::2, 0::1, _::1, 0::1, 0::1, _::1, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, end_headers: false, padded: false, priority: false}}
  end

  def decode(flags, <<_::2, 0::1, _::1, 0::1, 0::1, _::1, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, end_headers: false, padded: false, priority: false}}
  end

  def decode(flags, <<_::2, 0::1, _::1, 0::1, 1::1, _::1, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, end_headers: true, padded: false, priority: false}}
  end

  def decode(flags, <<_::2, 0::1, _::1, 1::1, 1::1, _::1, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, end_headers: true, padded: true, priority: false}}
  end

  def decode(flags, <<_::2, 1::1, _::1, 1::1, 1::1, _::1, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, end_headers: true, padded: true, priority: true}}
  end

  def decode(flags, <<_::2, 1::1, _::1, 1::1, 1::1, _::1, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, end_headers: true, padded: true, priority: true}}
  end

  def decode(flags, <<_::2, 1::1, _::1, 1::1, 0::1, _::1, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, end_headers: false, padded: true, priority: true}}
  end

  def decode(flags, <<_::2, 1::1, _::1, 0::1, 0::1, _::1, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, end_headers: false, padded: false, priority: true}}
  end

  def decode(flags, <<_::2, 1::1, _::1, 0::1, 0::1, _::1, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, end_headers: false, padded: false, priority: true}}
  end

  def decode(flags, <<_::2, 1::1, _::1, 0::1, 1::1, _::1, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, end_headers: true, padded: false, priority: true}}
  end

  def decode(flags, <<_::2, 1::1, _::1, 1::1, 0::1, _::1, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, end_headers: false, padded: true, priority: true}}
  end

  def decode(flags, <<_::2, 0::1, _::1, 1::1, 0::1, _::1, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, end_headers: false, padded: true, priority: false}}
  end

  def decode(flags, <<_::2, 0::1, _::1, 1::1, 0::1, _::1, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, end_headers: false, padded: true, priority: false}}
  end

  def decode(flags, <<_::2, 0::1, _::1, 0::1, 1::1, _::1, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, end_headers: true, padded: false, priority: false}}
  end

  def decode(flags, <<_::2, 1::1, _::1, 0::1, 1::1, _::1, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, end_headers: true, padded: false, priority: true}}
  end

  def decode(flags, <<_::2, 0::1, _::1, 1::1, 1::1, _::1, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, end_headers: true, padded: true, priority: false}}
  end

  def decode(_flags, _data, _options), do: {:error, :decode_error}

  def encode(%{end_stream: false, end_headers: false, padded: false, priority: false}, _) do
    {:ok, <<0::2, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>}
  end

  def encode(%{end_stream: true, end_headers: false, padded: false, priority: false}, _) do
    {:ok, <<0::2, 0::1, 0::1, 0::1, 0::1, 0::1, 1::1>>}
  end

  def encode(%{end_stream: true, end_headers: true, padded: false, priority: false}, _) do
    {:ok, <<0::2, 0::1, 0::1, 0::1, 1::1, 0::1, 1::1>>}
  end

  def encode(%{end_stream: true, end_headers: true, padded: true, priority: false}, _) do
    {:ok, <<0::2, 0::1, 0::1, 1::1, 1::1, 0::1, 1::1>>}
  end

  def encode(%{end_stream: true, end_headers: true, padded: true, priority: true}, _) do
    {:ok, <<0::2, 1::1, 0::1, 1::1, 1::1, 0::1, 1::1>>}
  end

  def encode(%{end_stream: false, end_headers: true, padded: true, priority: true}, _) do
    {:ok, <<0::2, 1::1, 0::1, 1::1, 1::1, 0::1, 0::1>>}
  end

  def encode(%{end_stream: false, end_headers: false, padded: true, priority: true}, _) do
    {:ok, <<0::2, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1>>}
  end

  def encode(%{end_stream: false, end_headers: false, padded: false, priority: true}, _) do
    {:ok, <<0::2, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1>>}
  end

  def encode(%{end_stream: true, end_headers: false, padded: false, priority: true}, _) do
    {:ok, <<0::2, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1>>}
  end

  def encode(%{end_stream: true, end_headers: true, padded: false, priority: true}, _) do
    {:ok, <<0::2, 1::1, 0::1, 0::1, 1::1, 0::1, 1::1>>}
  end

  def encode(%{end_stream: true, end_headers: false, padded: true, priority: true}, _) do
    {:ok, <<0::2, 1::1, 0::1, 1::1, 0::1, 0::1, 1::1>>}
  end

  def encode(%{end_stream: true, end_headers: false, padded: true, priority: false}, _) do
    {:ok, <<0::2, 0::1, 0::1, 1::1, 0::1, 0::1, 1::1>>}
  end

  def encode(%{end_stream: false, end_headers: false, padded: true, priority: false}, _) do
    {:ok, <<0::2, 0::1, 0::1, 1::1, 0::1, 0::1, 0::1>>}
  end

  def encode(%{end_stream: false, end_headers: true, padded: false, priority: false}, _) do
    {:ok, <<0::2, 0::1, 0::1, 0::1, 1::1, 0::1, 0::1>>}
  end

  def encode(%{end_stream: false, end_headers: true, padded: false, priority: true}, _) do
    {:ok, <<0::2, 1::1, 0::1, 0::1, 1::1, 0::1, 0::1>>}
  end

  def encode(%{end_stream: false, end_headers: true, padded: true, priority: false}, _) do
    {:ok, <<0::2, 0::1, 0::1, 1::1, 1::1, 0::1, 0::1>>}
  end

  def encode(_flags, _options), do: {:error, :encode_error}
end
