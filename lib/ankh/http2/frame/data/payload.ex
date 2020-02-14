defmodule Ankh.HTTP2.Frame.Data.Payload do
  @moduledoc false

  @type t :: %__MODULE__{pad_length: integer, data: binary}
  defstruct pad_length: 0, data: <<>>
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Data.Payload do
  def decode(payload, <<pad_length::8, padded_data::binary>>, flags: %{padded: true}) do
    data = binary_part(padded_data, 0, byte_size(padded_data) - pad_length)
    {:ok, %{payload | pad_length: pad_length, data: data}}
  end

  def decode(payload, <<data::binary>>, flags: %{padded: false}) do
    {:ok, %{payload | data: data}}
  end

  def decode(_payload, _data, _options), do: {:error, :decode_error}

  def encode(%{pad_length: pad_length, data: data}, flags: %{padded: true}) do
    {:ok, [<<pad_length::8, data>>, :binary.copy(<<0>>, pad_length)]}
  end

  def encode(%{data: data}, flags: %{padded: false}) do
    {:ok, [data]}
  end

  def encode(_payload, _options), do: {:error, :encode_error}
end
