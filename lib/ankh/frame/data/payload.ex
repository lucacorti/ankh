defmodule Ankh.Frame.Data.Payload do
  @moduledoc false

  @type t :: %__MODULE__{pad_length: integer, data: binary}
  defstruct pad_length: 0, data: <<>>
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.Data.Payload do
  def decode!(payload, <<pad_length::8, padded_data::binary>>, flags: %{padded: true}) do
    data = binary_part(padded_data, 0, byte_size(padded_data) - pad_length)
    %{payload | pad_length: pad_length, data: data}
  end

  def decode!(payload, <<data::binary>>, flags: %{padded: false}) do
    %{payload | data: data}
  end

  def encode!(%{pad_length: pad_length, data: data}, flags: %{padded: true}) do
    [<<pad_length::8, data>>, :binary.copy(<<0>>, pad_length)]
  end

  def encode!(%{data: data}, flags: %{padded: false}) do
    [data]
  end
end
