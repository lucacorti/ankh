defmodule Ankh.HTTP2.Frame do
  @moduledoc """
  HTTP/2 frame struct

  The __using__ macro injects the frame struct needed by `Ankh.HTTP2.Frame`.
  """

  require Logger

  alias Ankh.HTTP2.Frame.Encodable

  @typedoc "Struct injected by the `Ankh.HTTP2.Frame` __using__ macro."
  @type t :: struct()

  @typedoc "Frame length"
  @type length :: non_neg_integer()

  @typedoc "Frame type code"
  @type type :: non_neg_integer()

  @typedoc "Frame data"
  @type data :: iodata()

  @typedoc "Encode/Decode options"
  @type options :: Keyword.t()

  @header_size 9

  @doc """
  Injects the frame struct in a module.

  - type: HTTP/2 frame type code
  - flags: data type implementing `Ankh.HTTP2.Frame.Encodable`
  - payload: data type implementing `Ankh.HTTP2.Frame.Encodable`
  """
  @spec __using__(type: type, flags: atom | nil, payload: atom | nil) :: Macro.t()
  defmacro __using__(args) do
    with {:ok, type} <- Keyword.fetch(args, :type),
         flags <- Keyword.get(args, :flags),
         payload <- Keyword.get(args, :payload) do
      quote bind_quoted: [type: type, flags: flags, payload: payload] do
        @typedoc """
        - length: payload length in bytes
        - flags: data type implementing `Ankh.HTTP2.Frame.Encodable`
        - stream_id: Stream ID of the frame
        - payload: data type implementing `Ankh.HTTP2.Frame.Encodable`
        """
        @type t :: %__MODULE__{
                length: integer,
                type: integer,
                stream_id: integer,
                flags: Encodable.t() | nil,
                payload: Encodable.t() | nil
              }

        flags = if flags, do: struct(flags), else: nil
        payload = if payload, do: struct(payload), else: nil

        defstruct length: 0,
                  type: type,
                  stream_id: 0,
                  flags: flags,
                  payload: payload
      end
    else
      :error ->
        raise "Missing type code: You must provide a type code for the frame"
    end
  end

  @doc """
  Decodes a binary into a frame struct

  Parameters:
    - struct: struct using `Ankh.HTTP2.Frame`
    - binary: data to decode into the struct
    - options: options to pass as context to the decoding function
  """
  @spec decode(t, binary, options) :: {:ok, t} | {:error, any()}
  def decode(frame, data, options \\ [])

  def decode(frame, <<0::24, _type::8, flags::binary-size(1), _reserved::1, id::31>>, options) do
    with {:ok, flags} <- Encodable.decode(frame.flags, flags, options),
         do: {:ok, %{frame | stream_id: id, flags: flags, payload: nil}}
  end

  def decode(
        frame,
        <<length::24, _type::8, flags::binary-size(1), _reserved::1, id::31, payload::binary>>,
        options
      ) do
    with {:ok, flags} <- Encodable.decode(frame.flags, flags, options),
         payload_options <- Keyword.put(options, :flags, flags),
         {:ok, payload} <- Encodable.decode(frame.payload, payload, payload_options),
         do: {:ok, %{frame | length: length, stream_id: id, flags: flags, payload: payload}}
  end

  @doc """
  Encodes a frame struct into binary

  Parameters:
    - struct: struct using `Ankh.HTTP2.Frame`
    - options: options to pass as context to the encoding function
  """
  @spec encode(t(), options) :: {:ok, t(), data} | {:error, any()}
  def encode(frame, options \\ [])

  def encode(%{type: type, flags: flags, stream_id: id, payload: nil} = frame, options) do
    with {:ok, flags} <- Encodable.encode(flags, options) do
      {
        :ok,
        frame,
        [<<0::24, type::8, flags::binary-size(1), 0::1, id::31>>]
      }
    end
  end

  def encode(%{type: type, flags: nil, stream_id: id, payload: payload} = frame, options) do
    with {:ok, payload} <- Encodable.encode(payload, options) do
      length = IO.iodata_length(payload)

      {
        :ok,
        %{frame | length: length},
        [<<length::24, type::8, 0::8, 0::1, id::31>> | payload]
      }
    end
  end

  def encode(%{type: type, stream_id: id, flags: flags, payload: payload} = frame, options) do
    payload_options = Keyword.put(options, :flags, flags)

    with {:ok, payload} <- Encodable.encode(payload, payload_options),
         {:ok, flags} <- Encodable.encode(flags, options) do
      length = IO.iodata_length(payload)

      {
        :ok,
        %{frame | length: length},
        [<<length::24, type::8, flags::binary-size(1), 0::1, id::31>> | payload]
      }
    end
  end

  @doc """
  Returns s tream of frames from a buffer, returning the leftover buffer data
  and the frame header information and data (without decoding it) in a tuple:

  `{remaining_buffer, {length, type, id, frame_data}}`

  or nil to signal partial leftover data:

  `{remaining_buffer, nil}`
  """
  @spec stream(iodata()) :: Enumerable.t()
  def stream(data) do
    Stream.unfold(data, fn
      <<length::24, type::8, _flags::binary-size(1), _reserved::1, id::31, rest::binary>> = data
      when byte_size(rest) >= length ->
        frame_size = @header_size + length
        frame_data = binary_part(data, 0, frame_size)
        rest_size = byte_size(data) - frame_size
        rest_data = binary_part(data, frame_size, rest_size)
        {{rest_data, {length, type, id, frame_data}}, rest_data}

      data when byte_size(data) == 0 ->
        nil

      data ->
        {{data, nil}, data}
    end)
  end
end
