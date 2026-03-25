defmodule Ankh.Protocol.HTTP3.QPACK do
  @moduledoc """
  QPACK header compression for HTTP/3 (RFC 9204), mirroring the HPAX API
  used by the HTTP/2 implementation in Ankh.

  ## API mirror

  This module exposes an API that is intentionally identical in shape to
  [HPAX](https://hex.pm/packages/hpax) (the HPACK library used for HTTP/2),
  making it straightforward to swap between the two:

  | HPAX function       | `Ankh.Protocol.HTTP3.QPACK` function    |
  |---------------------|--------------------------|
  | `HPAX.new/1`        | `Ankh.Protocol.HTTP3.QPACK.new/1`       |
  | `HPAX.encode/3`     | `Ankh.Protocol.HTTP3.QPACK.encode/3`    |
  | `HPAX.decode/2`     | `Ankh.Protocol.HTTP3.QPACK.decode/2`    |
  | `HPAX.resize/2`     | `Ankh.Protocol.HTTP3.QPACK.resize/2`    |

  ## Static-only mode (Required Insert Count = 0)

  This implementation uses **static-only** QPACK, meaning every header block
  is encoded with Required Insert Count = 0.  No entries are ever inserted
  into the dynamic table, so no encoder stream or decoder stream is required.
  This mode is always valid per RFC 9204 and is the correct starting point for
  an HTTP/3 implementation before dynamic table negotiation is supported.

  Every encoded header block starts with the two-byte prefix `<<0x00, 0x00>>`:

    - Byte 0: Required Insert Count = 0, 8-bit prefix integer → `0x00`
    - Byte 1: Sign bit = 0, Delta Base = 0, 7-bit prefix integer → `0x00`

  After the prefix, each header field is encoded as one of:

    1. **Indexed Field Line** (RFC 9204 §4.5.2) — when both name and value
       match a static table entry. First byte: `0xC0 | index` (6-bit prefix,
       T = 1 for static).
    2. **Literal with Static Name Reference** (§4.5.4) — when only the name
       matches a static table entry. First byte: `0x50 | name_index` (N = 0)
       or `0x70 | name_index` (N = 1), 4-bit prefix, T = 1; followed by a
       length-prefixed value string.
    3. **Literal without Name Reference** (§4.5.6) — no static table match.
       First byte: `0x20 | name_length` (N = 0) or `0x30 | name_length`
       (N = 1), 3-bit prefix, H = 0; followed by the raw name bytes and a
       length-prefixed value string.

  Huffman encoding is never applied on the encode path; H = 0 (raw bytes) is
  always valid.  Huffman-encoded strings are decoded correctly on the receive
  path.

  ## Usage

      # Initialise a QPACK state (dynamic table disabled by default)
      qpack = Ankh.Protocol.HTTP3.QPACK.new()

      # Encode a list of {name, value} headers
      {encoded_block, qpack} = Ankh.Protocol.HTTP3.QPACK.encode(:store, headers, qpack)

      # Decode a received header block binary
      {:ok, headers, qpack} = Ankh.Protocol.HTTP3.QPACK.decode(encoded_block, qpack)

      # Resize the dynamic table capacity (for future dynamic-table support)
      qpack = Ankh.Protocol.HTTP3.QPACK.resize(qpack, 4096)

  ## Sensitivity

  The `sensitivity` argument to `encode/3` controls the **N** (never-index)
  bit in literal field representations:

    - `:store`       — the field may be indexed; N = 0
    - `:no_store`    — prefer not to index, but it is permitted; N = 0
    - `:never_store` — must never be added to any index; N = 1

  Indexed field representations do not carry an N bit and are therefore
  unaffected by the sensitivity setting.
  """

  import Bitwise

  alias Ankh.Protocol.HTTP3.QPACK.{Huffman, StaticTable, Table}

  @opaque t :: %__MODULE__{
            table: Table.t()
          }

  @typedoc "Public alias for `t/0`, mirroring `HPAX.table/0`."
  @type table :: t()

  @typedoc """
  Controls whether a literal header field representation carries the
  never-index (N) bit.

    - `:store`       — N = 0; the field may be indexed by intermediaries
    - `:no_store`    — N = 0; the encoder prefers not to index, but permits it
    - `:never_store` — N = 1; the field must never be indexed
  """
  @type sensitivity :: :store | :no_store | :never_store

  @enforce_keys [:table]
  defstruct table: nil

  # Two-byte header block prefix for static-only encoding (RFC 9204 §4.5.1):
  #   Byte 0 — Required Insert Count = 0 encoded with an 8-bit prefix → 0x00
  #   Byte 1 — S = 0, Delta Base = 0 encoded with a 7-bit prefix     → 0x00
  @prefix <<0x00, 0x00>>

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Create a new QPACK state.

  `max_table_capacity` sets the maximum size in bytes of the dynamic table.
  Defaults to `0`, which disables the dynamic table entirely and keeps the
  encoder in static-only mode.

  ## Examples

      iex> Ankh.Protocol.HTTP3.QPACK.new()
      %Ankh.Protocol.HTTP3.QPACK{table: %Ankh.Protocol.HTTP3.QPACK.Table{max_capacity: 0, size: 0}}

      iex> Ankh.Protocol.HTTP3.QPACK.new(4096)
      %Ankh.Protocol.HTTP3.QPACK{table: %Ankh.Protocol.HTTP3.QPACK.Table{max_capacity: 4096, size: 0}}

  """
  @spec new(non_neg_integer()) :: t()
  def new(max_table_capacity \\ 0)
      when is_integer(max_table_capacity) and max_table_capacity >= 0 do
    %__MODULE__{table: Table.new(max_table_capacity)}
  end

  @doc """
  Encode a list of header fields into a QPACK header block.

  Returns `{encoded, new_qpack}` where `encoded` is `iodata()` ready to be
  written into a QUIC HEADERS frame payload, and `new_qpack` is the updated
  QPACK state.

  The header block always begins with the 2-byte static-only prefix
  `<<0x00, 0x00>>`, followed by one field representation per `{name, value}`
  pair in wire order.

  ### Encoding strategy (in priority order)

  1. `{name, value}` matches a static table entry exactly →
     **Indexed Field Line** (most compact; no N bit).
  2. `name` alone matches a static table entry →
     **Literal with Static Name Reference** (N bit set per `sensitivity`).
  3. No static table match →
     **Literal without Name Reference** (N bit set per `sensitivity`).

  Strings are always written with H = 0 (raw bytes, no Huffman compression).

  ## Examples

      iex> qpack = Ankh.Protocol.HTTP3.QPACK.new()
      iex> {encoded, _qpack} = Ankh.Protocol.HTTP3.QPACK.encode(:store, [{":method", "GET"}], qpack)
      iex> is_list(encoded)
      true

  """
  @spec encode(sensitivity(), [{binary(), binary()}], t()) :: {iodata(), t()}
  def encode(sensitivity, headers, %__MODULE__{table: table} = qpack)
      when sensitivity in [:store, :no_store, :never_store] and is_list(headers) do
    never_index = sensitivity == :never_store

    fields =
      Enum.map(headers, fn {name, value} ->
        encode_field(name, value, never_index)
      end)

    {[@prefix | fields], %__MODULE__{qpack | table: table}}
  end

  @doc """
  Decode a QPACK-encoded header block.

  Returns `{:ok, headers, new_qpack}` on success, where `headers` is a list
  of `{name, value}` binaries in the order they appear in the block.

  Returns `{:error, reason}` on failure:

    - `:invalid_prefix` — `binary` does not begin with `<<0x00, 0x00>>`
    - `:dynamic_table_not_supported` — a field references the dynamic table
    - `:invalid_static_index` — a static table index is out of range (0–98)
    - `:huffman_error` — Huffman decoding failed on a string field
    - `:truncated` — the binary ended unexpectedly mid-field
    - `:invalid_data` — any other structural decoding error

  ## Examples

      iex> qpack = Ankh.Protocol.HTTP3.QPACK.new()
      iex> {encoded, qpack} = Ankh.Protocol.HTTP3.QPACK.encode(:store, [{":method", "GET"}], qpack)
      iex> {:ok, headers, _qpack} = Ankh.Protocol.HTTP3.QPACK.decode(IO.iodata_to_binary(encoded), qpack)
      iex> headers
      [{":method", "GET"}]

  """
  @spec decode(binary(), t()) :: {:ok, [{binary(), binary()}], t()} | {:error, atom()}
  def decode(<<0x00, 0x00, rest::binary>>, %__MODULE__{table: table} = qpack) do
    case decode_fields(rest, table, []) do
      {:ok, headers, new_table} -> {:ok, headers, %__MODULE__{qpack | table: new_table}}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_data}
  end

  def decode(_binary, _qpack), do: {:error, :invalid_prefix}

  @doc """
  Resize the QPACK dynamic table to a new maximum capacity.

  Evicts the oldest entries first when the new capacity is smaller than the
  current occupied size.  Setting `max_table_capacity` to `0` disables the
  dynamic table entirely.

  ## Examples

      iex> qpack = Ankh.Protocol.HTTP3.QPACK.new(4096)
      iex> qpack = Ankh.Protocol.HTTP3.QPACK.resize(qpack, 0)
      iex> qpack.table.max_capacity
      0

  """
  @spec resize(t(), non_neg_integer()) :: t()
  def resize(%__MODULE__{table: table} = qpack, max_table_capacity)
      when is_integer(max_table_capacity) and max_table_capacity >= 0 do
    %__MODULE__{qpack | table: Table.resize(table, max_table_capacity)}
  end

  # ---------------------------------------------------------------------------
  # Private: field encoding
  # ---------------------------------------------------------------------------

  # Encode a single {name, value} pair using the best available representation.
  @spec encode_field(binary(), binary(), boolean()) :: iodata()
  defp encode_field(name, value, never_index) do
    case StaticTable.find_name_value(name, value) do
      {:ok, index} ->
        # Exact match → Indexed Field Line (static) — RFC 9204 §4.5.2
        encode_indexed_static(index)

      :error ->
        case StaticTable.find_name(name) do
          {:ok, name_index} ->
            # Name-only match → Literal with Static Name Reference — §4.5.4
            encode_literal_name_ref_static(name_index, value, never_index)

          :error ->
            # No match → Literal without Name Reference — §4.5.6
            encode_literal_no_name_ref(name, value, never_index)
        end
    end
  end

  # Indexed Field Line (static) — RFC 9204 §4.5.2
  #
  # First-byte layout:
  #   bit 7    = 1      (Indexed Field Line marker)
  #   bit 6    = T = 1  (static table reference)
  #   bits 5:0 = Index  (6-bit prefix integer; header byte = 0b11000000 = 0xC0)
  @spec encode_indexed_static(non_neg_integer()) :: iodata()
  defp encode_indexed_static(index) do
    encode_integer(6, 0xC0, index)
  end

  # Literal Field Line With Name Reference (static) — RFC 9204 §4.5.4
  #
  # First-byte layout:
  #   bit 7    = 0
  #   bit 6    = 1      (Literal With Name Reference marker)
  #   bit 5    = N      (never-index flag)
  #   bit 4    = T = 1  (static table reference)
  #   bits 3:0 = Name Index (4-bit prefix integer)
  #   → header byte = 0x50 when N = 0, 0x70 when N = 1
  # Then: value string  (H = 0 bit + 7-bit length + raw bytes)
  @spec encode_literal_name_ref_static(non_neg_integer(), binary(), boolean()) :: iodata()
  defp encode_literal_name_ref_static(name_index, value, never_index) do
    header_byte = if never_index, do: 0x70, else: 0x50
    [encode_integer(4, header_byte, name_index), encode_string(value)]
  end

  # Literal Field Line Without Name Reference — RFC 9204 §4.5.6
  #
  # First-byte layout:
  #   bit 7    = 0
  #   bit 6    = 0
  #   bit 5    = 1      (Literal Without Name Reference marker)
  #   bit 4    = N      (never-index flag)
  #   bit 3    = H = 0  (no Huffman encoding for the name)
  #   bits 2:0 = NameLen (3-bit prefix integer)
  #   → header byte = 0x20 when N = 0, 0x30 when N = 1
  # Then: raw name bytes, then value string (H bit + 7-bit length + raw bytes)
  @spec encode_literal_no_name_ref(binary(), binary(), boolean()) :: iodata()
  defp encode_literal_no_name_ref(name, value, never_index) do
    header_byte = if never_index, do: 0x30, else: 0x20
    [encode_integer(3, header_byte, byte_size(name)), name, encode_string(value)]
  end

  # Encode a QPACK string with H = 0 (no Huffman):
  #   H = 0 is stored in bit 7 of the first byte (header_byte = 0x00).
  #   The byte count follows as a 7-bit prefix integer.
  #   The raw bytes follow immediately.
  @spec encode_string(binary()) :: iodata()
  defp encode_string(value) do
    [encode_integer(7, 0x00, byte_size(value)), value]
  end

  # ---------------------------------------------------------------------------
  # Private: integer encoding (RFC 9204 §4.1.1 ≡ RFC 7541 §5.1)
  # ---------------------------------------------------------------------------

  # Encode `value` as a prefix integer with `prefix_bits` bits.
  # `header_byte` supplies the fixed high-order flag bits that occupy the
  # positions above the prefix in the first encoded byte.
  #
  # When value < 2^prefix_bits - 1, the whole integer fits in the first byte.
  # Otherwise the first byte carries the all-ones sentinel and the remainder is
  # expressed in one or more 7-bit continuation bytes.
  @spec encode_integer(pos_integer(), non_neg_integer(), non_neg_integer()) :: iodata()
  defp encode_integer(prefix_bits, header_byte, value) do
    max = (1 <<< prefix_bits) - 1

    if value < max do
      [<<header_byte ||| value>>]
    else
      [<<header_byte ||| max>> | encode_integer_continuation(value - max)]
    end
  end

  # Emit multi-byte continuation octets for the portion of an integer that
  # overflowed the prefix.
  #
  # Each continuation byte encodes 7 bits of the remaining value; the high bit
  # (bit 7) is set to 1 when another byte follows, and 0 on the final byte.
  #
  # When the remainder is exactly 0 (i.e. the original value equalled the
  # prefix maximum 2^N - 1), we must still emit <<0>> so the decoder correctly
  # terminates the continuation sequence.  The `n < 128` guard handles n = 0
  # by producing [<<0>>].
  @spec encode_integer_continuation(non_neg_integer()) :: iolist()
  defp encode_integer_continuation(n) when n < 128, do: [<<n>>]

  defp encode_integer_continuation(n) do
    [<<(n &&& 0x7F) ||| 0x80>> | encode_integer_continuation(n >>> 7)]
  end

  # ---------------------------------------------------------------------------
  # Private: field decoding (RFC 9204 §4.5)
  # ---------------------------------------------------------------------------

  @spec decode_fields(binary(), Table.t(), [{binary(), binary()}]) ::
          {:ok, [{binary(), binary()}], Table.t()} | {:error, atom()}

  # All field lines consumed — return accumulated headers in wire order.
  defp decode_fields(<<>>, table, acc) do
    {:ok, Enum.reverse(acc), table}
  end

  # Indexed Field Line — bit 7 = 1  (§4.5.2 static / §4.5.3 post-base dynamic)
  defp decode_fields(<<1::1, _::bits>> = data, table, acc) do
    decode_indexed(data, table, acc)
  end

  # Literal Field Line With Name Reference — bits 7:6 = 01  (§4.5.4 / §4.5.5)
  defp decode_fields(<<0::1, 1::1, _::bits>> = data, table, acc) do
    decode_literal_name_ref(data, table, acc)
  end

  # Literal Field Line Without Name Reference — bits 7:5 = 001  (§4.5.6)
  defp decode_fields(<<0::1, 0::1, 1::1, _::bits>> = data, table, acc) do
    decode_literal_no_name_ref(data, table, acc)
  end

  # Post-Base Indexed Field Line — bits 7:4 = 0001  (§4.5.3, dynamic table only)
  defp decode_fields(<<0::1, 0::1, 0::1, 1::1, _::bits>>, _table, _acc) do
    {:error, :dynamic_table_not_supported}
  end

  # Post-Base Literal Field Line With Name Reference — bits 7:4 = 0000  (§4.5.5)
  defp decode_fields(<<0::1, 0::1, 0::1, 0::1, _::bits>>, _table, _acc) do
    {:error, :dynamic_table_not_supported}
  end

  # Indexed Field Line — RFC 9204 §4.5.2 (static) and §4.5.3 (post-base dynamic)
  #
  # First-byte layout: 1 T Index(6+)
  #   bit 6    = T: 1 = static table, 0 = post-base dynamic table
  #   bits 5:0 = Index as a 6-bit prefix integer
  @spec decode_indexed(binary(), Table.t(), [{binary(), binary()}]) ::
          {:ok, [{binary(), binary()}], Table.t()} | {:error, atom()}
  defp decode_indexed(<<byte, _::binary>> = data, table, acc) do
    static? = (byte &&& 0x40) != 0
    {index, rest} = decode_integer(6, data)

    if static? do
      case StaticTable.lookup(index) do
        {:ok, header} -> decode_fields(rest, table, [header | acc])
        :error -> {:error, :invalid_static_index}
      end
    else
      {:error, :dynamic_table_not_supported}
    end
  end

  # Literal Field Line With Name Reference — RFC 9204 §4.5.4 (static)
  #
  # First-byte layout: 0 1 N T NameIndex(4+)
  #   bit 5    = N: never-index flag (informational on decode)
  #   bit 4    = T: 1 = static table, 0 = dynamic table
  #   bits 3:0 = Name Index as a 4-bit prefix integer
  # Then: value string  (H bit + 7-bit length + bytes)
  @spec decode_literal_name_ref(binary(), Table.t(), [{binary(), binary()}]) ::
          {:ok, [{binary(), binary()}], Table.t()} | {:error, atom()}
  defp decode_literal_name_ref(<<byte, _::binary>> = data, table, acc) do
    static? = (byte &&& 0x10) != 0
    {name_index, rest} = decode_integer(4, data)

    if static? do
      with {:ok, {name, _cached_value}} <- StaticTable.lookup(name_index),
           {:ok, value, rest2} <- decode_string(rest) do
        decode_fields(rest2, table, [{name, value} | acc])
      else
        :error -> {:error, :invalid_static_index}
        {:error, _} = err -> err
      end
    else
      {:error, :dynamic_table_not_supported}
    end
  end

  # Literal Field Line Without Name Reference — RFC 9204 §4.5.6
  #
  # First-byte layout: 0 0 1 N H NameLen(3+)
  #   bit 4    = N: never-index flag (informational on decode)
  #   bit 3    = H: Huffman flag for the name bytes
  #   bits 2:0 = Name length as a 3-bit prefix integer
  #
  # The H bit for the name sits at bit 3, which is above the 3-bit prefix
  # mask (0x07), so it does not affect the length integer decoded by
  # `decode_integer/2` and must be extracted separately.
  #
  # Then: raw (or Huffman-decoded) name bytes
  # Then: value string  (H bit + 7-bit length + bytes)
  @spec decode_literal_no_name_ref(binary(), Table.t(), [{binary(), binary()}]) ::
          {:ok, [{binary(), binary()}], Table.t()} | {:error, atom()}
  defp decode_literal_no_name_ref(<<byte, _::binary>> = data, table, acc) do
    huffman_name? = (byte &&& 0x08) != 0
    {name_length, rest} = decode_integer(3, data)

    case read_string_data(rest, name_length, huffman_name?) do
      {:ok, name, rest2} ->
        case decode_string(rest2) do
          {:ok, value, rest3} -> decode_fields(rest3, table, [{name, value} | acc])
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  # Decode a standard QPACK string:
  #   bit 7 of the first byte = H (Huffman flag)
  #   bits 6:0 of the first byte = start of a 7-bit prefix integer for length
  #   then `length` bytes of string data (raw or Huffman-encoded)
  @spec decode_string(binary()) :: {:ok, binary(), binary()} | {:error, atom()}
  defp decode_string(<<byte, _::binary>> = data) do
    huffman? = (byte &&& 0x80) != 0
    {length, rest} = decode_integer(7, data)
    read_string_data(rest, length, huffman?)
  end

  defp decode_string(<<>>), do: {:error, :truncated}

  # Read exactly `length` bytes from `data`, applying Huffman decoding when
  # `huffman?` is true.  Returns `{:error, :truncated}` when fewer than
  # `length` bytes are available.
  @spec read_string_data(binary(), non_neg_integer(), boolean()) ::
          {:ok, binary(), binary()} | {:error, atom()}
  defp read_string_data(data, length, huffman?) do
    if byte_size(data) < length do
      {:error, :truncated}
    else
      <<raw::binary-size(length), rest::binary>> = data
      apply_huffman(raw, rest, huffman?)
    end
  end

  @spec apply_huffman(binary(), binary(), boolean()) ::
          {:ok, binary(), binary()} | {:error, atom()}
  defp apply_huffman(raw, rest, false), do: {:ok, raw, rest}

  defp apply_huffman(raw, rest, true) do
    case Huffman.decode(raw) do
      {:ok, decoded} -> {:ok, decoded, rest}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: integer decoding (RFC 9204 §4.1.1 ≡ RFC 7541 §5.1)
  # ---------------------------------------------------------------------------

  # Decode a prefix integer with `prefix_bits` bits from `data`.
  #
  # The upper bits of the first byte (those above the prefix) are format flags
  # and are masked away before inspecting the integer value.  When the masked
  # value is less than 2^prefix_bits - 1, the integer fits in that single byte.
  # When it equals the maximum, additional continuation bytes are consumed.
  @spec decode_integer(pos_integer(), binary()) :: {non_neg_integer(), binary()}
  defp decode_integer(prefix_bits, <<first_byte, rest::binary>>) do
    mask = (1 <<< prefix_bits) - 1
    value = first_byte &&& mask

    if value < mask do
      {value, rest}
    else
      decode_integer_continuation(rest, value, 0)
    end
  end

  # Accumulate 7-bit continuation bytes into the integer value.
  #
  # Each byte contributes 7 bits (bits 6:0) shifted left by `shift` positions
  # relative to the current accumulator.  Bit 7 of each byte indicates whether
  # another continuation byte follows (1 = more, 0 = last byte).
  @spec decode_integer_continuation(binary(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), binary()}
  defp decode_integer_continuation(<<byte, rest::binary>>, acc, shift) do
    new_acc = acc + ((byte &&& 0x7F) <<< shift)

    if (byte &&& 0x80) != 0 do
      decode_integer_continuation(rest, new_acc, shift + 7)
    else
      {new_acc, rest}
    end
  end
end
