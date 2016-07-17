defmodule Http2.Frame.PushPromise.Payload do
  defstruct [pad_length: 0, promised_stream_id: 0, header_block_fragment: nil]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.PushPromise.Payload do
  alias Http2.Frame.PushPromise.{Flags, Payload}

  import Http2.Frame.Encoder.Utils

  def encode!(%Payload{pad_length: pl, promised_stream_id: psi,
  header_block_fragment: hbf}, flags: %Flags{padded: true})
  do
    <<pl::8, 0::1, psi::31>> <> hbf <> padding(pl)
  end

  def encode!(%Payload{promised_stream_id: psi, header_block_fragment: hbf},
   flags: %Flags{padded: false}) do
    <<0::1, psi::31>> <> hbf
  end

  def decode!(struct, <<pl::8, _::1, psi::31, data::binary>>,
  flags: %Flags{padded: true}) do
    hbf = binary_part(data, 0, byte_size(data) - pl)
    %{struct | pad_length: pl, promised_stream_id: psi,
      header_block_fragment: hbf}
  end

  def decode!(struct, <<_::8, _::1, psi::31, hbf::binary>>,
  flags: %Flags{padded: false}) do
      %{struct | promised_stream_id: psi, header_block_fragment: hbf}
  end
end
