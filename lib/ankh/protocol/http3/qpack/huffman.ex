defmodule Ankh.Protocol.HTTP3.QPACK.Huffman do
  @moduledoc """
  Huffman encoding and decoding for QPACK and HPACK, implementing the static
  Huffman code defined in RFC 7541 Appendix B.

  The symbol alphabet has 257 entries: byte values 0–255 plus the EOS
  (end-of-string) symbol 256.  Code lengths range from 5 bits (common ASCII
  printable characters) to 30 bits (EOS and rare control characters).

  ## Encoding

  Each input byte is looked up in the compile-time `@encode_table` to obtain
  its `{code_integer, bit_length}` pair.  Codes are packed left-to-right into
  an accumulator integer; the final incomplete byte is padded on the right
  with `1`-bits — the most-significant bits of the EOS code — as required by
  RFC 7541 § 5.2.

  ## Decoding

  A prefix trie is built at compile time (`@decode_trie`) from the Huffman
  table.  The trie is a flat `%{node_id => {child_for_0, child_for_1}}` map
  where each child is `{:leaf, symbol}`, `{:node, id}`, or `nil`.  Input bits
  are consumed one at a time; upon reaching a leaf the decoded byte is emitted
  and traversal restarts from the root (node 0).

  At end-of-input, 1–7 trailing `1`-bits are accepted as valid EOS padding
  (RFC 7541 § 5.2).  Any other trailing trie state, EOS appearing mid-stream,
  or an unrecognised bit sequence is rejected with `{:error, :huffman_error}`.

  ### Note on symbol 249

  A common transcription of the RFC 7541 table writes symbol 249 as
  `{0xfffffe, 28}` (6 hex digits).  The RFC itself specifies `ffffffe [28]`
  (7 hex digits, code integer `0xffffffe`).  The shorter form would create a
  prefix collision with symbol 49 (`'1'`, 5-bit code `0x1 = 00001`).  This
  module uses the RFC-correct value `0xffffffe`.
  """

  import Bitwise

  # ---------------------------------------------------------------------------
  # RFC 7541 Appendix B Huffman code table
  # {symbol, code_integer, code_length_in_bits}
  # All 257 entries — symbols 0–255 (byte values) plus 256 (EOS).
  # ---------------------------------------------------------------------------

  @table [
    # Control characters 0–31
    {0, 0x1FF8, 13},
    {1, 0x7FFFD8, 23},
    {2, 0xFFFFFE2, 28},
    {3, 0xFFFFFE3, 28},
    {4, 0xFFFFFE4, 28},
    {5, 0xFFFFFE5, 28},
    {6, 0xFFFFFE6, 28},
    {7, 0xFFFFFE7, 28},
    {8, 0xFFFFFE8, 28},
    {9, 0xFFFFEA, 24},
    {10, 0x3FFFFFFC, 30},
    {11, 0xFFFFFE9, 28},
    {12, 0xFFFFFEA, 28},
    {13, 0x3FFFFFFD, 30},
    {14, 0xFFFFFEB, 28},
    {15, 0xFFFFFEC, 28},
    {16, 0xFFFFFED, 28},
    {17, 0xFFFFFEE, 28},
    {18, 0xFFFFFEF, 28},
    {19, 0xFFFFFF0, 28},
    {20, 0xFFFFFF1, 28},
    {21, 0xFFFFFF2, 28},
    {22, 0x3FFFFFFE, 30},
    {23, 0xFFFFFF3, 28},
    {24, 0xFFFFFF4, 28},
    {25, 0xFFFFFF5, 28},
    {26, 0xFFFFFF6, 28},
    {27, 0xFFFFFF7, 28},
    {28, 0xFFFFFF8, 28},
    {29, 0xFFFFFF9, 28},
    {30, 0xFFFFFFA, 28},
    {31, 0xFFFFFFB, 28},
    # Printable ASCII 32–126
    # ' '
    {32, 0x14, 6},
    # '!'
    {33, 0x3F8, 10},
    # '"'
    {34, 0x3F9, 10},
    # '#'
    {35, 0xFFA, 12},
    # '$'
    {36, 0x1FF9, 13},
    # '%'
    {37, 0x15, 6},
    # '&'
    {38, 0xF8, 8},
    # '\''
    {39, 0x7FA, 11},
    # '('
    {40, 0x3FA, 10},
    # ')'
    {41, 0x3FB, 10},
    # '*'
    {42, 0xF9, 8},
    # '+'
    {43, 0x7FB, 11},
    # ','
    {44, 0xFA, 8},
    # '-'
    {45, 0x16, 6},
    # '.'
    {46, 0x17, 6},
    # '/'
    {47, 0x18, 6},
    # '0'
    {48, 0x0, 5},
    # '1'
    {49, 0x1, 5},
    # '2'
    {50, 0x2, 5},
    # '3'
    {51, 0x19, 6},
    # '4'
    {52, 0x1A, 6},
    # '5'
    {53, 0x1B, 6},
    # '6'
    {54, 0x1C, 6},
    # '7'
    {55, 0x1D, 6},
    # '8'
    {56, 0x1E, 6},
    # '9'
    {57, 0x1F, 6},
    # ':'
    {58, 0x5C, 7},
    # ';'
    {59, 0xFB, 8},
    # '<'
    {60, 0x7FFC, 15},
    # '='
    {61, 0x20, 6},
    # '>'
    {62, 0xFFB, 12},
    # '?'
    {63, 0x3FC, 10},
    # '@'
    {64, 0x1FFA, 13},
    # 'A'
    {65, 0x21, 6},
    # 'B'
    {66, 0x5D, 7},
    # 'C'
    {67, 0x5E, 7},
    # 'D'
    {68, 0x5F, 7},
    # 'E'
    {69, 0x60, 7},
    # 'F'
    {70, 0x61, 7},
    # 'G'
    {71, 0x62, 7},
    # 'H'
    {72, 0x63, 7},
    # 'I'
    {73, 0x64, 7},
    # 'J'
    {74, 0x65, 7},
    # 'K'
    {75, 0x66, 7},
    # 'L'
    {76, 0x67, 7},
    # 'M'
    {77, 0x68, 7},
    # 'N'
    {78, 0x69, 7},
    # 'O'
    {79, 0x6A, 7},
    # 'P'
    {80, 0x6B, 7},
    # 'Q'
    {81, 0x6C, 7},
    # 'R'
    {82, 0x6D, 7},
    # 'S'
    {83, 0x6E, 7},
    # 'T'
    {84, 0x6F, 7},
    # 'U'
    {85, 0x70, 7},
    # 'V'
    {86, 0x71, 7},
    # 'W'
    {87, 0x72, 7},
    # 'X'
    {88, 0xFC, 8},
    # 'Y'
    {89, 0x73, 7},
    # 'Z'
    {90, 0xFD, 8},
    # '['
    {91, 0x1FFB, 13},
    # '\'
    {92, 0x7FFF0, 19},
    # ']'
    {93, 0x1FFC, 13},
    # '^'
    {94, 0x3FFC, 14},
    # '_'
    {95, 0x22, 6},
    # '`'
    {96, 0x7FFD, 15},
    # 'a'
    {97, 0x3, 5},
    # 'b'
    {98, 0x23, 6},
    # 'c'
    {99, 0x4, 5},
    # 'd'
    {100, 0x24, 6},
    # 'e'
    {101, 0x5, 5},
    # 'f'
    {102, 0x25, 6},
    # 'g'
    {103, 0x26, 6},
    # 'h'
    {104, 0x27, 6},
    # 'i'
    {105, 0x6, 5},
    # 'j'
    {106, 0x74, 7},
    # 'k'
    {107, 0x75, 7},
    # 'l'
    {108, 0x28, 6},
    # 'm'
    {109, 0x29, 6},
    # 'n'
    {110, 0x2A, 6},
    # 'o'
    {111, 0x7, 5},
    # 'p'
    {112, 0x2B, 6},
    # 'q'
    {113, 0x76, 7},
    # 'r'
    {114, 0x2C, 6},
    # 's'
    {115, 0x8, 5},
    # 't'
    {116, 0x9, 5},
    # 'u'
    {117, 0x2D, 6},
    # 'v'
    {118, 0x77, 7},
    # 'w'
    {119, 0x78, 7},
    # 'x'
    {120, 0x79, 7},
    # 'y'
    {121, 0x7A, 7},
    # 'z'
    {122, 0x7B, 7},
    # '{'
    {123, 0x7FFE, 15},
    # '|'
    {124, 0x7FC, 11},
    # '}'
    {125, 0x3FFD, 14},
    # '~'
    {126, 0x1FFD, 13},
    # Extended / non-printable 127–255
    {127, 0xFFFFFFC, 28},
    {128, 0xFFFE6, 20},
    {129, 0x3FFFD2, 22},
    {130, 0xFFFE7, 20},
    {131, 0xFFFE8, 20},
    {132, 0x3FFFD3, 22},
    {133, 0x3FFFD4, 22},
    {134, 0x3FFFD5, 22},
    {135, 0x7FFFD9, 23},
    {136, 0x3FFFD6, 22},
    {137, 0x7FFFDA, 23},
    {138, 0x7FFFDB, 23},
    {139, 0x7FFFDC, 23},
    {140, 0x7FFFDD, 23},
    {141, 0x7FFFDE, 23},
    {142, 0xFFFFEB, 24},
    {143, 0x7FFFDF, 23},
    {144, 0xFFFFEC, 24},
    {145, 0xFFFFED, 24},
    {146, 0x3FFFD7, 22},
    {147, 0x7FFFE0, 23},
    {148, 0xFFFFEE, 24},
    {149, 0x7FFFE1, 23},
    {150, 0x7FFFE2, 23},
    {151, 0x7FFFE3, 23},
    {152, 0x7FFFE4, 23},
    {153, 0x1FFFDC, 21},
    {154, 0x3FFFD8, 22},
    {155, 0x7FFFE5, 23},
    {156, 0x3FFFD9, 22},
    {157, 0x7FFFE6, 23},
    {158, 0x7FFFE7, 23},
    {159, 0xFFFFEF, 24},
    {160, 0x3FFFDA, 22},
    {161, 0x1FFFDD, 21},
    {162, 0xFFFE9, 20},
    {163, 0x3FFFDB, 22},
    {164, 0x3FFFDC, 22},
    {165, 0x7FFFE8, 23},
    {166, 0x7FFFE9, 23},
    {167, 0x1FFFDE, 21},
    {168, 0x7FFFEA, 23},
    {169, 0x3FFFDD, 22},
    {170, 0x3FFFDE, 22},
    {171, 0xFFFFF0, 24},
    {172, 0x1FFFDF, 21},
    {173, 0x3FFFDF, 22},
    {174, 0x7FFFEB, 23},
    {175, 0x7FFFEC, 23},
    {176, 0x1FFFE0, 21},
    {177, 0x1FFFE1, 21},
    {178, 0x3FFFE0, 22},
    {179, 0x1FFFE2, 21},
    {180, 0x7FFFED, 23},
    {181, 0x3FFFE1, 22},
    {182, 0x7FFFEE, 23},
    {183, 0x7FFFEF, 23},
    {184, 0xFFFEA, 20},
    {185, 0x3FFFE2, 22},
    {186, 0x3FFFE3, 22},
    {187, 0x3FFFE4, 22},
    {188, 0x7FFFF0, 23},
    {189, 0x3FFFE5, 22},
    {190, 0x3FFFE6, 22},
    {191, 0x7FFFF1, 23},
    {192, 0x3FFFFE0, 26},
    {193, 0x3FFFFE1, 26},
    {194, 0xFFFEB, 20},
    {195, 0x7FFF1, 19},
    {196, 0x3FFFE7, 22},
    {197, 0x7FFFF2, 23},
    {198, 0x3FFFE8, 22},
    {199, 0x1FFFFEC, 25},
    {200, 0x3FFFFE2, 26},
    {201, 0x3FFFFE3, 26},
    {202, 0x3FFFFE4, 26},
    {203, 0x7FFFFDE, 27},
    {204, 0x7FFFFDF, 27},
    {205, 0x3FFFFE5, 26},
    {206, 0xFFFFF1, 24},
    {207, 0x1FFFFED, 25},
    {208, 0x7FFF2, 19},
    {209, 0x1FFFE3, 21},
    {210, 0x3FFFFE6, 26},
    {211, 0x7FFFFE0, 27},
    {212, 0x7FFFFE1, 27},
    {213, 0x3FFFFE7, 26},
    {214, 0x7FFFFE2, 27},
    {215, 0xFFFFF2, 24},
    {216, 0x1FFFE4, 21},
    {217, 0x1FFFE5, 21},
    {218, 0x3FFFFE8, 26},
    {219, 0x3FFFFE9, 26},
    {220, 0xFFFFFFD, 28},
    {221, 0x7FFFFE3, 27},
    {222, 0x7FFFFE4, 27},
    {223, 0x7FFFFE5, 27},
    {224, 0xFFFEC, 20},
    {225, 0xFFFFF3, 24},
    {226, 0xFFFED, 20},
    {227, 0x1FFFE6, 21},
    {228, 0x3FFFE9, 22},
    {229, 0x1FFFE7, 21},
    {230, 0x1FFFE8, 21},
    {231, 0x7FFFF3, 23},
    {232, 0x3FFFEA, 22},
    {233, 0x3FFFEB, 22},
    {234, 0x1FFFFEE, 25},
    {235, 0x1FFFFEF, 25},
    {236, 0xFFFFF4, 24},
    {237, 0xFFFFF5, 24},
    {238, 0x3FFFFEA, 26},
    {239, 0x7FFFF4, 23},
    {240, 0x3FFFFEB, 26},
    {241, 0x7FFFFE6, 27},
    {242, 0x3FFFFEC, 26},
    {243, 0x3FFFFED, 26},
    {244, 0x7FFFFE7, 27},
    {245, 0x7FFFFE8, 27},
    {246, 0x7FFFFE9, 27},
    {247, 0x7FFFFEA, 27},
    {248, 0x7FFFFEB, 27},
    # RFC 7541: ffffffe [28] — 27 ones followed by 0.
    # A common transcription error writes this as 0xfffffe (24-bit value)
    # which collides with symbol 49 ('1').  The correct value is 0xffffffe.
    {249, 0xFFFFFFE, 28},
    {250, 0x7FFFFEC, 27},
    {251, 0x7FFFFED, 27},
    {252, 0x7FFFFEE, 27},
    {253, 0x7FFFFEF, 27},
    {254, 0x7FFFFF0, 27},
    {255, 0x3FFFFEE, 26},
    # EOS — end-of-string; used only as padding prefix, never encoded directly.
    {256, 0x3FFFFFFF, 30}
  ]

  # ---------------------------------------------------------------------------
  # Compile-time encode table: byte_value => {code_integer, code_length_in_bits}
  # EOS (256) is excluded — it is never encoded directly.
  # ---------------------------------------------------------------------------

  @encode_table (for {sym, code, len} <- @table, sym < 256, into: %{} do
                   {sym, {code, len}}
                 end)

  # ---------------------------------------------------------------------------
  # Compile-time decode trie.
  #
  # Representation: %{node_id => {child_for_bit_0, child_for_bit_1}}
  #   where each child is one of:
  #     {:leaf, symbol}   — a complete Huffman code ends here
  #     {:node, node_id}  — continue traversal
  #     nil               — no valid code takes this branch
  #
  # Root is node 0; new node IDs are assigned sequentially.
  #
  # For each table entry we extract the code bits MSB-first, walk the trie
  # (creating internal nodes on demand), and place a {:leaf, symbol} at the
  # terminal position.
  # ---------------------------------------------------------------------------

  @decode_trie Enum.reduce(
                 @table,
                 {%{0 => {nil, nil}}, 1},
                 fn {symbol, code, len}, {trie, next_id} ->
                   # Extract bits MSB-first.
                   bits = for i <- (len - 1)..0//-1, do: band(bsr(code, i), 1)

                   # Everything except the last bit forms the path through internal nodes.
                   {path_bits, [last_bit]} = Enum.split(bits, len - 1)

                   # Walk the internal-node path, creating nodes as needed.
                   # We use `tr`/`nxt` inside the inner reduce to avoid rebinding the
                   # outer `trie`/`next_id` before we are done with them.
                   {trie, next_id, leaf_parent} =
                     Enum.reduce(path_bits, {trie, next_id, 0}, fn bit, {tr, nxt, cur} ->
                       {c0, c1} = Map.get(tr, cur, {nil, nil})
                       existing_child = if bit == 0, do: c0, else: c1

                       {child_id, tr, nxt} =
                         case existing_child do
                           {:node, id} ->
                             # Node already exists; just descend.
                             {id, tr, nxt}

                           nil ->
                             # Create a fresh internal node and update the parent pointer.
                             new_id = nxt
                             tr = Map.put(tr, new_id, {nil, nil})

                             updated_parent =
                               if bit == 0,
                                 do: {{:node, new_id}, c1},
                                 else: {c0, {:node, new_id}}

                             {new_id, Map.put(tr, cur, updated_parent), nxt + 1}
                         end

                       {tr, nxt, child_id}
                     end)

                   # Place the leaf at the last-bit position of the leaf's parent node.
                   {c0, c1} = Map.get(trie, leaf_parent, {nil, nil})

                   leaf_entry =
                     if last_bit == 0,
                       do: {{:leaf, symbol}, c1},
                       else: {c0, {:leaf, symbol}}

                   {Map.put(trie, leaf_parent, leaf_entry), next_id}
                 end
               )
               |> elem(0)

  # ---------------------------------------------------------------------------
  # Compile-time valid padding terminal nodes.
  #
  # After the last decoded symbol, the remaining 1–7 bits must be all `1`s
  # (the EOS prefix, RFC 7541 § 5.2).  In the trie those bits lead exclusively
  # rightward (bit = 1) — the same path as EOS (30 ones).  We precompute the
  # node IDs at depths 1–7 on that all-ones path so that end-of-stream
  # validation is a single O(1) MapSet lookup.
  # ---------------------------------------------------------------------------

  @padding_valid_nodes Enum.reduce_while(
                         1..7,
                         {0, MapSet.new()},
                         fn _, {cur_id, valid_set} ->
                           case @decode_trie[cur_id] do
                             {_c0, {:node, next_id}} ->
                               {:cont, {next_id, MapSet.put(valid_set, next_id)}}

                             _ ->
                               # EOS path shorter than 7 — should not happen with a correct table.
                               {:halt, {cur_id, valid_set}}
                           end
                         end
                       )
                       |> elem(1)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Decode a Huffman-encoded binary according to RFC 7541 Appendix B.

  Returns `{:ok, decoded_binary}` on success.

  Returns `{:error, :huffman_error}` when:

  * an unrecognised bit sequence is encountered;
  * the EOS symbol (256) appears mid-stream;
  * trailing padding is longer than 7 bits; or
  * trailing padding bits are not all `1`s.

  ## Examples

      iex> Ankh.Protocol.HTTP3.QPACK.Huffman.decode(<<0x1f>>)
      {:ok, "a"}

      iex> Ankh.Protocol.HTTP3.QPACK.Huffman.decode(<<>>)
      {:ok, ""}

  """
  @spec decode(binary()) :: {:ok, binary()} | {:error, :huffman_error}
  def decode(data) when is_binary(data) do
    decode_bits(data, 0, [])
  end

  @doc """
  Encode a binary using the RFC 7541 Huffman code.

  Each byte in `data` is replaced by its variable-length Huffman code.  The
  resulting bit stream is padded on the right to the next byte boundary with
  `1`-bits (the EOS prefix), as required by RFC 7541 § 5.2.

  Encoding never fails; every byte value 0–255 has a table entry.

  ## Examples

      iex> Ankh.Protocol.HTTP3.QPACK.Huffman.encode("a")
      <<0x1f>>

      iex> Ankh.Protocol.HTTP3.QPACK.Huffman.encode("")
      <<>>

  """
  @spec encode(binary()) :: binary()
  def encode(data) when is_binary(data) do
    # Accumulate all codes into a single arbitrary-precision integer together
    # with the running bit count.
    {bits, length} =
      :binary.bin_to_list(data)
      |> Enum.reduce({0, 0}, fn byte, {acc_bits, acc_len} ->
        {code, len} = Map.fetch!(@encode_table, byte)
        {bor(bsl(acc_bits, len), code), acc_len + len}
      end)

    # Pad the last byte to a byte boundary with 1-bits.
    # rem(8 - rem(length, 8), 8) yields 0 when length is already aligned.
    padding = rem(8 - rem(length, 8), 8)
    total_bits = length + padding
    # bsl(1, padding) - 1 produces `padding` ones; harmless when padding == 0.
    padded_bits = bor(bsl(bits, padding), bsl(1, padding) - 1)

    case total_bits do
      0 -> <<>>
      n -> <<padded_bits::integer-size(n)>>
    end
  end

  # ---------------------------------------------------------------------------
  # Private: recursive bit-by-bit trie traversal
  # ---------------------------------------------------------------------------

  # End of input sitting at the trie root — all symbols decoded, no padding.
  defp decode_bits(<<>>, 0, acc) do
    {:ok, :erlang.list_to_binary(Enum.reverse(acc))}
  end

  # End of input at an intermediate node.  Valid iff those bits were 1–7 all-one
  # padding bits, i.e. the node is on the all-ones (EOS prefix) path at depth
  # 1–7.
  defp decode_bits(<<>>, node_id, acc) do
    if MapSet.member?(@padding_valid_nodes, node_id) do
      {:ok, :erlang.list_to_binary(Enum.reverse(acc))}
    else
      {:error, :huffman_error}
    end
  end

  # Consume one bit and advance through the trie.
  defp decode_bits(<<bit::1, rest::bitstring>>, node_id, acc) do
    case @decode_trie[node_id] do
      nil ->
        # node_id not in trie — should not happen with a valid trie.
        {:error, :huffman_error}

      {child0, child1} ->
        child = if bit == 0, do: child0, else: child1

        case child do
          # EOS appearing mid-stream is always an error (RFC 7541 § 5.2).
          {:leaf, 256} ->
            {:error, :huffman_error}

          # Decoded a complete symbol; emit it and restart from the root.
          {:leaf, sym} ->
            decode_bits(rest, 0, [sym | acc])

          # Partial code; continue deeper in the trie.
          {:node, next_id} ->
            decode_bits(rest, next_id, acc)

          # No Huffman code starts with this bit sequence.
          nil ->
            {:error, :huffman_error}
        end
    end
  end
end
