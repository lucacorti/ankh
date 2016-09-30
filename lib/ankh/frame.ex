defmodule Ankh.Frame do
  @moduledoc """
  HTTP/2 frame behaviour
  """

  @typedoc """
  Frame struct
  """
  @type t :: struct

  defmacro __using__(type: type, flags: flags, payload: payload) do
    unless is_integer(type) do
      raise CompileError, "Frame type must be Integer.t"
    end

    quote do
      alias Ankh.Frame.Encoder

      @type_code unquote(type)

      @typedoc """
      - length: payload length in bytes
      - flags: `Ankh.Frame.Flags` conforming struct
      - stream_id: Stream ID of the frame
      - payload: `Ankh.Frame.Payload` conforming struct
      """
      @type t :: %__MODULE__{length: Integer.t, stream_id: Integer.t,
      flags: unquote(flags), payload: unquote(payload)}
      defstruct [length: 0, flags: nil, stream_id: 0, payload: nil]

      def decode!(frame, <<0::24, @type_code::8, flags::binary-size(1),
      0x0::1, id::31>>, options) do
        flags = Encoder.decode!(%unquote(flags){}, flags, options)
        %{frame | stream_id: id, flags: flags}
      end

      def decode!(frame, <<length::24, @type_code::8, flags::binary-size(1),
      0x0::1, id::31, payload::binary>>, options) do
        flags = Encoder.decode!(%unquote(flags){}, flags, options)
        payload_opts = [flags: flags] ++ options
        %{frame | length: length stream_id: id, flags: flags,
        payload: Encoder.decode!(%unquote(payload){}, payload, payload_opts)}
      end

      def encode!(%{flags: flags, stream_id: id, payload: nil}, options) do
        flags = Encoder.encode!(flags, options)
        <<0::24, @type_code::8>> <> flags <> <<0x0::1, id::31>>
      end

      def encode!(%{flags: nil, stream_id: id, payload: payload}, options) do
        payload = Encoder.encode!(payload, options)
        length = byte_size(payload)
        <<length::24, @type_code::8, 0x0::8, 0x0::1, id::31>> <> payload
      end

      def encode!(%{stream_id: id, flags: flags, payload: payload}, options) do
        payload = Encoder.encode!(payload, [flags: flags] ++ options)
        length = byte_size(payload)
        flags = Encoder.encode!(flags, options)
        <<length::24, @type_code::8>> <> flags <> <<0x0::1, id::31>> <> payload
      end
    end
  end
end
