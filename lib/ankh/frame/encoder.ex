defprotocol Ankh.Frame.Encoder do
  @moduledoc """
  Protocol for encoding/decoding frame structs

  Expects a struct with the format injected by `use Ankh.Frame`
  """
  @fallback_to_any true

  @typedoc """
  Struct conforming to the `Ankh.Frame.Encoder` protocol
  """
  @type t :: struct

  @doc """
  Decodes a binary into a conforming struct

  Parameters:
    - struct: struct conforming to the `Ankh.Frame.Encoder` protocol
    - binary: data to decode into the struct
    - options: options to pass as context to the decoding function
  """
  @spec decode!(t, binary, Keyword.t) :: t
  def decode!(struct, binary, options)

  @doc """
  Encodes a conforming struct into binary

  Parameters:
    - struct: struct conforming to the `Ankh.Frame.Encoder` protocol
    - options: options to pass as context to the encoding function
  """
  @spec encode!(t, Keyword.t) :: binary
  def encode!(struct, options)
end

defimpl Ankh.Frame.Encoder, for: Any do
  alias Ankh.Frame.{Flags, Payload}

  def decode!(frame, <<0::24, _type::8, flags::binary-size(1),
  0x0::1, id::31>>, options) do
    flags = Flags.decode!(frame.flags, flags, options)
    %{frame | stream_id: id, flags: flags}
  end

  def decode!(frame, <<length::24, _type::8, flags::binary-size(1),
  0x0::1, id::31, payload::binary>>, options) do
    flags = Flags.decode!(frame.flags, flags, options)
    payload_opts = [flags: flags] ++ options
    payload = Payload.decode!(frame.payload, payload, payload_opts)
    %{frame | length: length, stream_id: id, flags: flags, payload: payload}
  end

  def encode!(%{type: type, flags: flags, stream_id: id, payload: nil}, options)
  do
    flags = Flags.encode!(flags, options)
    <<0::24, type::8>> <> flags <> <<0x0::1, id::31>>
  end

  def encode!(%{type: type, flags: nil, stream_id: id, payload: payload},
  options) do
    payload = Payload.encode!(payload, options)
    length = byte_size(payload)
    <<length::24, type::8, 0x0::8, 0x0::1, id::31>> <> payload
  end

  def encode!(%{type: type, stream_id: id, flags: flags, payload: payload},
  options) do
    payload = Payload.encode!(payload, [flags: flags] ++ options)
    length = byte_size(payload)
    flags = Flags.encode!(flags, options)
    <<length::24, type::8>> <> flags <> <<0x0::1, id::31>> <> payload
  end
end
