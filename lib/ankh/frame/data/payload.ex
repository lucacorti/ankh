defmodule Ankh.Frame.Data.Payload do
  @moduledoc """
  DATA frame payload
  """

  @type t :: %__MODULE__{pad_length: Integer.t, data: binary}
  defstruct [pad_length: 0, data: <<>>]
end

defimpl Ankh.Frame.Payload, for: Ankh.Frame.Data.Payload do
  import Ankh.Frame.Utils

  def decode!(struct, <<pad_length::8, padded_data::binary>>,
  flags: %{padded: true}) do
    data = binary_part(padded_data, 0, byte_size(padded_data) - pad_length)
    %{struct | pad_length: pad_length, data: data}
  end

  def decode!(struct, <<data::binary>>, flags: %{padded: false}) do
    %{struct | data: data}
  end

  def encode!(%{pad_length: pad_length, data: data}, flags: %{padded: true}) do
    [<<pad_length::8, data>>, padding(pad_length)]
  end

  def encode!(%{data: data}, flags: %{padded: false}) do
    [data]
  end
end
