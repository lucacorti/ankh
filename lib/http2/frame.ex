defmodule Http2.Frame do
  defstruct [length: 0, type: nil, flags: nil, stream_id: 0, payload: nil]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame do
  alias Http2.Frame
  alias Http2.Frame.Encoder

  @reserved      0x0

  @data          0x0
  @headers       0x1
  @priority      0x2
  @rst_stream    0x3
  @settings      0x4
  @push_promise  0x5
  @ping          0x6
  @goaway        0x7
  @window_update 0x8
  @continuation  0x9

  def decode!(frame, <<0::24, t::8, f::binary-1, 0x0::1, id::31>>, options) do
    type = decode_type!(t)
    flags = Encoder.decode!(flags_for_type!(t), f, options)
    %Frame{frame | type: type, stream_id: id, flags: flags}
  end

  def decode!(frame, <<l::24, t::8, f::binary-1, 0x0::1, id::31, p::binary>>,
  options) do
    type = decode_type!(t)
    flags = Encoder.decode!(flags_for_type!(t), f, options)
    payload_opts = [flags: flags] ++ options
    %Frame{frame | length: l, type: type, stream_id: id, flags: flags}
    |> Map.put(:payload, Encoder.decode!(payload_for_type!(t), p, payload_opts))
  end

  def encode!(%Frame{type: type, flags: f, stream_id: id, payload: nil},
  options) do
    flags = Encoder.encode!(f, options)
    <<0::24, encode_type!(type)::8>> <> flags <> <<@reserved::1, id::31>>
  end

  def encode!(%Frame{type: type, flags: nil, stream_id: id, payload: p},
  options) do
    payload = Encoder.encode!(p, options)
    length = byte_size(payload)
    <<length::24, encode_type!(type)::8, 0::8, @reserved::1, id::31>> <> payload
  end

  def encode!(%Frame{type: type} = frame, options) do
    flags = Encoder.encode!(frame.flags, options)
    payload_opts = [flags: frame.flags] ++ options
    payload = Encoder.encode!(frame.payload, payload_opts)
    length = byte_size(payload)
    <<length::24, encode_type!(type)::8>> <> flags <> <<@reserved::1,
    frame.stream_id::31>> <> payload
  end

  defp encode_type!(:data), do:               @data
  defp encode_type!(:headers), do:            @headers
  defp encode_type!(:priority), do:           @priority
  defp encode_type!(:rst_stream), do:         @rst_stream
  defp encode_type!(:settings), do:           @settings
  defp encode_type!(:push_promise), do:       @push_promise
  defp encode_type!(:ping), do:               @ping
  defp encode_type!(:goaway), do:             @goaway
  defp encode_type!(:window_update), do:      @window_update
  defp encode_type!(:continuation), do:       @continuation

  defp decode_type!(@data), do:               :data
  defp decode_type!(@headers), do:            :headers
  defp decode_type!(@priority), do:           :priority
  defp decode_type!(@rst_stream), do:         :rst_stream
  defp decode_type!(@settings), do:           :settings
  defp decode_type!(@push_promise), do:       :push_promise
  defp decode_type!(@ping), do:               :ping
  defp decode_type!(@goaway), do:             :goaway
  defp decode_type!(@window_update), do:      :window_update
  defp decode_type!(@continuation), do:       :continuation
  defp decode_type!(_), do:                   :unknown

  defp flags_for_type!(@data), do:            %Frame.Data.Flags{}
  defp flags_for_type!(@headers), do:         %Frame.Headers.Flags{}
  defp flags_for_type!(@settings), do:        %Frame.Settings.Flags{}
  defp flags_for_type!(@push_promise), do:    %Frame.PushPromise.Flags{}
  defp flags_for_type!(@ping), do:            %Frame.Ping.Flags{}
  defp flags_for_type!(@continuation), do:    %Frame.Continuation.Flags{}
  defp flags_for_type!(_), do:                Any

  defp payload_for_type!(@data), do:          %Frame.Data.Payload{}
  defp payload_for_type!(@headers), do:       %Frame.Headers.Payload{}
  defp payload_for_type!(@priority), do:      %Frame.Priority.Payload{}
  defp payload_for_type!(@rst_stream), do:    %Frame.RstStream.Payload{}
  defp payload_for_type!(@settings), do:      %Frame.Settings.Payload{}
  defp payload_for_type!(@push_promise), do:  %Frame.PushPromise.Payload{}
  defp payload_for_type!(@ping), do:          %Frame.Ping.Payload{}
  defp payload_for_type!(@goaway), do:        %Frame.GoAway.Payload{}
  defp payload_for_type!(@window_update), do: %Frame.WindowUpdate.Payload{}
  defp payload_for_type!(@continuation), do:  %Frame.Continuation.Payload{}
  defp payload_for_type!(_), do:              Any
end
