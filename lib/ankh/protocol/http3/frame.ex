defmodule Ankh.Protocol.HTTP3.Frame do
  @moduledoc """
  HTTP/3 frame codec (RFC 9114) with a struct-based API that mirrors
  `Ankh.Protocol.HTTP2.Frame`.

  ## Design

  Every HTTP/3 frame type is represented as a dedicated module (e.g.
  `Ankh.Protocol.HTTP3.Frame.Data`) that calls

      use Ankh.Protocol.HTTP3.Frame, type: 0xN, payload: PayloadModule

  The macro injects a struct with three fields:

      %Frame.Data{type: 0, length: 0, payload: %Frame.Data.Payload{}}

  * `type`    — the integer frame type code, set at compile time.
  * `length`  — the payload byte count; filled in by `encode/1` and `decode/2`.
  * `payload` — a struct implementing `Ankh.Protocol.HTTP3.Frame.Encodable`.

  This is intentionally analogous to `Ankh.Protocol.HTTP2.Frame`, which uses
  the same `__using__` / `Encodable` / `stream` / `decode` / `encode`
  structure.  The main differences are:

  * HTTP/3 frames have **no flags byte** and **no stream-ID field** — those
    concerns belong to the QUIC layer.
  * Field lengths and frame-type codes are encoded as QUIC **variable-length
    integers** (VLIs, RFC 9000 §16) rather than fixed-width fields.

  ## QUIC Variable-Length Integer (VLI) encoding

  The two most-significant bits of the first byte indicate the total length:

  | MSBs | Length  | Value range               |
  |:----:|---------|---------------------------|
  | `00` | 1 byte  | 0 – 63                    |
  | `01` | 2 bytes | 0 – 16 383                |
  | `10` | 4 bytes | 0 – 1 073 741 823         |
  | `11` | 8 bytes | 0 – 4 611 686 018 427 387 903 |

  `encode_vli/1` always produces the smallest valid encoding; `decode_vli/1`
  reads the two prefix bits to determine width.

  ## Wire format

      Frame {
        Type   (VLI)
        Length (VLI)
        Payload (Length bytes)
      }

  `stream/1` lazily unfolds `{rest, {type_integer, payload_binary}}` pairs
  from a buffer binary — identical in spirit to `HTTP2.Frame.stream/1`, which
  unfolds `{rest, {length, type, id, data}}` tuples.  When the buffer ends with
  a partial frame a single `{data, nil}` element is emitted and the stream
  then terminates (next accumulator is `<<>>`), so callers can safely use
  `Enum.to_list/1` on buffers that contain only complete frames, and
  `Enum.reduce_while/3` (halting on the nil token) for streaming buffers.

  `decode/2` converts a `{frame_struct, payload_binary}` pair into a fully
  populated frame struct by delegating to `Encodable.decode/2`.

  `encode/1` turns a populated frame struct back into `{:ok, frame, iodata}`.
  """

  import Bitwise

  alias Ankh.Protocol.HTTP3.Frame.Encodable

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @typedoc "Frame type code (integer on the wire)."
  @type type :: non_neg_integer()

  @typedoc "Payload byte count."
  @type length :: non_neg_integer()

  @typedoc "Encoded frame data."
  @type data :: iodata()

  @typedoc "The generic frame struct injected by `__using__/1`."
  @type t :: struct()

  # ---------------------------------------------------------------------------
  # __using__ macro
  # ---------------------------------------------------------------------------

  @doc """
  Injects the frame struct into the calling module.

  Options:

  * `:type`    — (required) the integer HTTP/3 frame type code.
  * `:payload` — (optional) the module whose struct implements
    `Ankh.Protocol.HTTP3.Frame.Encodable`.  Defaults to `nil`, which uses the
    `Any` fallback (encodes/decodes as a no-op).

  The generated struct has fields:

  * `type`    — fixed at the value given to `:type`.
  * `length`  — number of encoded payload bytes; set during encode/decode.
  * `payload` — a struct (or `nil`) implementing `Encodable`.

  ## Example

      defmodule MyFrame do
        defmodule Payload do
          defstruct data: <<>>
          defimpl Ankh.Protocol.HTTP3.Frame.Encodable do
            def decode(%@for{} = p, bin), do: {:ok, %{p | data: bin}}
            def encode(%@for{data: d}), do: {:ok, d}
          end
        end

        use Ankh.Protocol.HTTP3.Frame, type: 0x99, payload: Payload
      end

      %MyFrame{type: 0x99, length: 0, payload: %MyFrame.Payload{}}
  """
  @spec __using__(type: type(), payload: atom() | nil) :: Macro.t()
  defmacro __using__(args) do
    case Keyword.fetch(args, :type) do
      {:ok, type} ->
        payload = Keyword.get(args, :payload)

        quote bind_quoted: [type: type, payload: payload] do
          alias Ankh.Protocol.HTTP3.Frame

          @typedoc """
          HTTP/3 frame struct.

          * `type`    — wire integer for this frame type (compile-time constant).
          * `length`  — payload size in bytes; populated by `Frame.encode/1` and
            `Frame.decode/2`.
          * `payload` — decoded payload struct (implements `Frame.Encodable`), or
            `nil` for frames with no payload.
          """
          @type t :: %__MODULE__{
                  type: Frame.type(),
                  length: Frame.length(),
                  payload: Frame.Encodable.t() | nil
                }

          payload_default = if payload, do: struct(payload), else: nil

          defstruct type: type,
                    length: 0,
                    payload: payload_default
        end

      :error ->
        raise ArgumentError,
              "#{__MODULE__}: `use Ankh.Protocol.HTTP3.Frame` requires a `:type` option"
    end
  end

  # ---------------------------------------------------------------------------
  # stream/1
  # ---------------------------------------------------------------------------

  @doc """
  Returns a lazy stream of `{rest, frame_token}` pairs unfolded from `data`.

  Each `frame_token` is either:

  * `{type_integer, payload_binary}` — a complete frame extracted from the
    buffer; `rest` is the remaining unconsumed binary.
  * `nil` — the buffer ends with a partial (incomplete) frame; `rest` is the
    full unconsumed binary that should be kept for the next delivery.

  The caller drives the stream with `Enum.reduce_while/3`, halting on `nil`
  to store the remainder and continuing on each complete frame.

  This mirrors `Ankh.Protocol.HTTP2.Frame.stream/1`, which yields
  `{rest, {length, type, id, data}}` tuples from a TCP buffer.

  ## Example

      iex> bin =
      ...>   IO.iodata_to_binary([
      ...>     Ankh.Protocol.HTTP3.Frame.encode_vli(0x1),   # HEADERS type
      ...>     Ankh.Protocol.HTTP3.Frame.encode_vli(3),     # length
      ...>     "hdr",
      ...>     Ankh.Protocol.HTTP3.Frame.encode_vli(0x0),   # DATA type
      ...>     Ankh.Protocol.HTTP3.Frame.encode_vli(2),     # length
      ...>     "hi"
      ...>   ])
      iex> Ankh.Protocol.HTTP3.Frame.stream(bin) |> Enum.map(fn {_rest, token} -> token end)
      [{1, "hdr"}, {0, "hi"}]
  """
  @spec stream(binary()) :: Enumerable.t()
  def stream(data) do
    Stream.unfold(data, fn
      <<>> ->
        nil

      data ->
        with {:ok, type, rest1} <- decode_vli(data),
             {:ok, length, rest2} <- decode_vli(rest1),
             true <- byte_size(rest2) >= length do
          <<payload::binary-size(length), rest3::binary>> = rest2
          {{rest3, {type, payload}}, rest3}
        else
          # Partial frame: emit one nil token then terminate the stream so
          # callers using Enum.to_list/1 don't loop forever.
          _ -> {{data, nil}, <<>>}
        end
    end)
  end

  # ---------------------------------------------------------------------------
  # decode/2
  # ---------------------------------------------------------------------------

  @doc """
  Decodes `payload_binary` into the given frame struct by delegating to
  `Encodable.decode/2` on the struct's `:payload` field.

  On success returns `{:ok, frame}` with `:length` set to
  `byte_size(payload_binary)` and `:payload` replaced by the decoded struct.

  ## Example

      frame = %Ankh.Protocol.HTTP3.Frame.Data{}
      {:ok, decoded} = Ankh.Protocol.HTTP3.Frame.decode(frame, "hello")
      # decoded.payload.data == "hello"
      # decoded.length == 5
  """
  @spec decode(t(), binary()) :: {:ok, t()} | {:error, any()}
  def decode(frame, payload_binary) when is_binary(payload_binary) do
    with {:ok, decoded_payload} <- Encodable.decode(frame.payload, payload_binary) do
      {:ok, %{frame | length: byte_size(payload_binary), payload: decoded_payload}}
    end
  end

  # ---------------------------------------------------------------------------
  # encode/1
  # ---------------------------------------------------------------------------

  @doc """
  Encodes a frame struct into its wire representation.

  Returns `{:ok, updated_frame, iodata}` where `iodata` is the complete
  on-wire frame (type VLI + length VLI + payload bytes) and `updated_frame`
  has its `:length` field set to the encoded payload byte count.

  ## Example

      frame = %Ankh.Protocol.HTTP3.Frame.Data{
        payload: %Ankh.Protocol.HTTP3.Frame.Data.Payload{data: "hi"}
      }
      {:ok, updated, iodata} = Ankh.Protocol.HTTP3.Frame.encode(frame)
      # updated.length == 2
      # IO.iodata_to_binary(iodata) == <<0x00, 0x02, ?h, ?i>>
  """
  @spec encode(t()) :: {:ok, t(), data()} | {:error, any()}
  def encode(%{type: type, payload: payload} = frame) do
    with {:ok, encoded_payload} <- Encodable.encode(payload) do
      payload_bin = IO.iodata_to_binary(encoded_payload)
      length = byte_size(payload_bin)

      {
        :ok,
        %{frame | length: length},
        [encode_vli(type), encode_vli(length), payload_bin]
      }
    end
  end

  # ---------------------------------------------------------------------------
  # VLI encode / decode
  # ---------------------------------------------------------------------------

  @doc """
  Encodes a non-negative integer as a QUIC variable-length integer.

  Always selects the smallest representation that fits the value.

  ## Examples

      iex> Ankh.Protocol.HTTP3.Frame.encode_vli(0)
      <<0>>

      iex> Ankh.Protocol.HTTP3.Frame.encode_vli(63)
      <<63>>

      iex> Ankh.Protocol.HTTP3.Frame.encode_vli(64)
      <<0x40, 64>>

      iex> Ankh.Protocol.HTTP3.Frame.encode_vli(16_383)
      <<0x7F, 0xFF>>

      iex> Ankh.Protocol.HTTP3.Frame.encode_vli(494)
      <<0x41, 0xEE>>
  """
  @spec encode_vli(non_neg_integer()) :: binary()
  def encode_vli(n) when n < 64, do: <<n>>
  def encode_vli(n) when n < 16_384, do: <<n ||| 0x4000::16>>
  def encode_vli(n) when n < 1_073_741_824, do: <<n ||| 0x80000000::32>>
  def encode_vli(n), do: <<n ||| 0xC000000000000000::64>>

  @doc """
  Decodes one QUIC variable-length integer from the front of `data`.

  Returns `{:ok, value, rest}` on success, or `{:error, :incomplete}` when
  there are not enough bytes for the width indicated by the prefix bits.

  ## Examples

      iex> Ankh.Protocol.HTTP3.Frame.decode_vli(<<0x41, 0xEE, "rest">>)
      {:ok, 494, "rest"}

      iex> Ankh.Protocol.HTTP3.Frame.decode_vli(<<7>>)
      {:ok, 7, ""}

      iex> Ankh.Protocol.HTTP3.Frame.decode_vli(<<>>)
      {:error, :incomplete}

      iex> Ankh.Protocol.HTTP3.Frame.decode_vli(<<0x40>>)
      {:error, :incomplete}
  """
  @spec decode_vli(binary()) :: {:ok, non_neg_integer(), binary()} | {:error, :incomplete}
  def decode_vli(<<0::2, n::6, rest::binary>>), do: {:ok, n, rest}
  def decode_vli(<<1::2, n::14, rest::binary>>), do: {:ok, n, rest}
  def decode_vli(<<2::2, n::30, rest::binary>>), do: {:ok, n, rest}
  def decode_vli(<<3::2, n::62, rest::binary>>), do: {:ok, n, rest}
  def decode_vli(_), do: {:error, :incomplete}

  # ---------------------------------------------------------------------------
  # Control stream preface
  # ---------------------------------------------------------------------------

  @control_stream_type 0x00

  # ---------------------------------------------------------------------------

  @doc """
  Returns the binary that MUST be written immediately after opening an HTTP/3
  control stream (RFC 9114 §6.2.1).

  The preface consists of:

  1. **Stream-type byte** `0x00` — marks this unidirectional QUIC stream as
     an HTTP/3 control stream.
  2. **SETTINGS frame** — type `0x04`, 4-byte payload:
     - `QPACK_MAX_TABLE_CAPACITY = 0` (`id = 0x01`, `value = 0x00`)
     - `QPACK_BLOCKED_STREAMS = 0`    (`id = 0x07`, `value = 0x00`)

  Advertising both settings at zero declares static-only QPACK mode, which
  requires no dedicated encoder or decoder streams.

  ## Example

      iex> Ankh.Protocol.HTTP3.Frame.control_stream_preface()
      <<0x00, 0x04, 0x04, 0x01, 0x00, 0x07, 0x00>>
  """
  @spec control_stream_preface() :: binary()
  def control_stream_preface do
    <<
      @control_stream_type,
      # SETTINGS frame type (VLI 1-byte)
      0x04,
      # SETTINGS payload length: 4 bytes (VLI 1-byte)
      0x04,
      # QPACK_MAX_TABLE_CAPACITY = 0  (id=0x01, value=0x00)
      0x01,
      0x00,
      # QPACK_BLOCKED_STREAMS = 0     (id=0x07, value=0x00)
      0x07,
      0x00
    >>
  end
end
