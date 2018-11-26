defmodule Ankh.Frame do
  @moduledoc """
  HTTP/2 frame struct

  The __using__ macro injects the frame struct needed by `Ankh.Frame`.
  """

  alias Ankh.Frame.{Encodable, Utils}

  @typedoc "Struct injected by the `Ankh.Frame` __using__ macro."
  @type t :: term | nil

  @typedoc "Encode/Decode options"
  @type options :: Keyword.t()

  @doc """
  Injects the frame struct in a module.

  - type: HTTP/2 frame type code
  - flags: frame flags struct or nil for no flags
  - payload: frame payload struct or nil for no payload
  """
  @spec __using__(type: Integer.t(), flags: Encodable.t(), payload: Encodable.t()) :: Macro.t()
  defmacro __using__(args) do
    with {:ok, type} <- Keyword.fetch(args, :type),
         flags <- Keyword.get(args, :flags),
         payload <- Keyword.get(args, :payload) do
      quote bind_quoted: [type: type, flags: flags, payload: payload] do
        @typedoc """
        - length: payload length in bytes
        - flags: data type implementing `Ankh.Frame.Encodable`
        - stream_id: Stream ID of the frame
        - payload: data type implementing `Ankh.Frame.Encodable`
        """
        @type t :: %__MODULE__{
                length: Integer.t(),
                stream_id: Integer.t(),
                flags: Encodable.t(),
                payload: Encodable.t()
              }

        defstruct length: 0, type: type, stream_id: 0, flags: flags, payload: payload
      end
    else
      :error ->
        raise "Missing type code: You must provide a type code for the frame"
    end
  end

  @doc """
  Decodes a binary into a frame struct

  Parameters:
    - struct: struct using `Ankh.Frame`
    - binary: data to decode into the struct
    - options: options to pass as context to the decoding function
  """
  @spec decode!(t, binary, options) :: t
  def decode!(frame, data, options \\ [])

  def decode!(frame, <<0::24, _type::8, flags::binary-size(1), 0::1, id::31>>, options) do
    flags = Encodable.decode!(frame.flags, flags, options)
    %{frame | stream_id: id, flags: flags}
  end

  def decode!(
        frame,
        <<length::24, _type::8, flags::binary-size(1), 0::1, id::31, payload::binary>>,
        options
      ) do
    flags = Encodable.decode!(frame.flags, flags, options)
    payload_options = Keyword.put(options, :flags, flags)
    payload = Encodable.decode!(frame.payload, payload, payload_options)
    %{frame | length: length, stream_id: id, flags: flags, payload: payload}
  end

  @doc """
  Encodes a frame struct into binary

  Parameters:
    - struct: struct using `Ankh.Frame`
    - options: options to pass as context to the encoding function
  """
  @spec encode!(t, options) :: iodata
  def encode!(frame, options \\ [])

  def encode!(%{type: type, flags: flags, stream_id: id, payload: nil}, options) do
    flags = Encodable.encode!(flags, options)
    [<<0::24, type::8>>, flags, <<0::1, id::31>>]
  end

  def encode!(%{type: type, flags: nil, stream_id: id, payload: payload}, options) do
    payload = Encodable.encode!(payload, options)
    length = IO.iodata_length(payload)
    [<<length::24, type::8, 0::8, 0::1, id::31>> | payload]
  end

  def encode!(%{type: type, stream_id: id, flags: flags, payload: payload}, options) do
    payload_options = Keyword.put(options, :flags, flags)
    payload = Encodable.encode!(payload, payload_options)
    length = IO.iodata_length(payload)
    flags = Encodable.encode!(flags, options)
    [<<length::24, type::8>>, flags, <<0::1, id::31>> | payload]
  end

  defdelegate split(frame, max_frame_size, end_stream \\ false), to: Utils
end
