defmodule Ankh.Frame.PushPromise.Payload do
  @moduledoc false

  @type t :: %__MODULE__{pad_length: integer, promised_stream_id: integer, hbf: binary}
  defstruct pad_length: 0, promised_stream_id: 0, hbf: <<>>
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.PushPromise.Payload do
  def decode(payload, <<pl::8, _::1, psi::31, data::binary>>, flags: %{padded: true}) do
    {:ok, %{payload | pad_length: pl, promised_stream_id: psi, hbf: binary_part(data, 0, byte_size(data) - pl)}}
  end

  def decode(payload, <<_::8, _::1, psi::31, hbf::binary>>, flags: %{padded: false}) do
    {:ok, %{payload | promised_stream_id: psi, hbf: hbf}}
  end

  def decode(_payload, _data, _options), do: {:error, :decode_error}

  def encode(
        %{pad_length: pad_length, promised_stream_id: psi, hbf: hbf},
        flags: %{padded: true}
      ) do
    {:ok, [<<pad_length::8, 0::1, psi::31>>, hbf, :binary.copy(<<0>>, pad_length)]}
  end

  def encode(%{promised_stream_id: psi, hbf: hbf}, flags: %{padded: false}) do
    {:ok, [<<0::1, psi::31>>, hbf]}
  end

  def encode(_payload, _options), do: {:error, :encode_error}
end
