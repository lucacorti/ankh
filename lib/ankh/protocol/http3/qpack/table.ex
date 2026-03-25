defmodule Ankh.Protocol.HTTP3.QPACK.Table do
  @moduledoc """
  QPACK dynamic table as described in RFC 9204, Section 2.2.

  ## Overview

  The QPACK dynamic table stores header field entries that accumulate over the
  lifetime of an HTTP/3 connection. Unlike HPACK (RFC 7541), QPACK maintains
  *separate* encoder and decoder tables that are synchronised via dedicated
  unidirectional QUIC streams (the encoder stream and the decoder stream). This
  separation allows the encoder to insert entries without blocking request
  processing, at the cost of a more complex acknowledgement protocol.

  Because of this split, instances of this module represent only *one side* of
  that pair. The `Ankh.Protocol.HTTP3.QPACK` encoder and decoder each own their own
  `Ankh.Protocol.HTTP3.QPACK.Table` and keep them in sync by exchanging instructions on the
  control streams.

  ## Capacity and the static-only mode

  When `max_capacity` is `0`—the default before the encoder sends a
  `Set Dynamic Table Capacity` instruction—no entries can be inserted and every
  header block must be encoded using static table references or literal field
  representations. This is the mode currently used by `Ankh.Protocol.HTTP3.QPACK`.

  ## Entry ordering and size

  Entries are stored newest-first (the head of `entries` is the most recently
  inserted entry), mirroring the HPACK convention. Each entry occupies:

      byte_size(name) + byte_size(value) + 32  bytes

  The 32-byte overhead accounts for estimated per-entry metadata, as defined in
  RFC 9204 § 3.2.1 (the same rule as HPACK § 4.1).

  ## insert_count

  `insert_count` is a monotonically increasing counter of all insertions ever
  made into the table. It is never decremented by evictions. QPACK uses it to
  derive the **Required Insert Count** field of encoded header blocks, which
  tells the decoder the minimum table state needed to decode a block
  (RFC 9204 § 3.2.6).

  ## Relative indexing

  QPACK addresses dynamic table entries with a *relative* index that is always
  interpreted with respect to a `base` value (the insertion count at encoding
  time). Relative index `0` refers to the most recently inserted entry when the
  header block was produced. See `lookup_relative/3` for the exact mapping.
  """

  @enforce_keys [:max_capacity]
  defstruct entries: [],
            size: 0,
            max_capacity: 0,
            insert_count: 0

  @type t :: %__MODULE__{
          entries: [{binary(), binary()}],
          size: non_neg_integer(),
          max_capacity: non_neg_integer(),
          insert_count: non_neg_integer()
        }

  # Per-entry size overhead defined in RFC 9204 § 3.2.1 (= HPACK § 4.1).
  @entry_overhead 32

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Create a new, empty dynamic table with the given maximum capacity in bytes.

  When `max_capacity` is `0`, the table is effectively disabled: any attempt to
  insert an entry will return `{:error, :too_large}` because no entry can ever
  fit within a zero-byte budget.

  ## Examples

      iex> Ankh.Protocol.HTTP3.QPACK.Table.new(4096)
      %Ankh.Protocol.HTTP3.QPACK.Table{max_capacity: 4096, size: 0, insert_count: 0, entries: []}

      iex> Ankh.Protocol.HTTP3.QPACK.Table.new(0)
      %Ankh.Protocol.HTTP3.QPACK.Table{max_capacity: 0, size: 0, insert_count: 0, entries: []}

  """
  @spec new(non_neg_integer()) :: t()
  def new(max_capacity) when is_integer(max_capacity) and max_capacity >= 0 do
    %__MODULE__{max_capacity: max_capacity}
  end

  @doc """
  Insert a new header field entry `{name, value}` into the dynamic table.

  The entry is prepended to `entries` (newest-first ordering). Before inserting,
  the oldest entries are evicted one by one—from the tail of the list—until the
  new entry can fit within `max_capacity`.

  Returns `{:error, :too_large}` when the entry's own size exceeds
  `max_capacity`, meaning the table could never accommodate it regardless of
  how many entries are evicted.

  ## Entry size formula

      byte_size(name) + byte_size(value) + 32

  ## Examples

      iex> table = Ankh.Protocol.HTTP3.QPACK.Table.new(4096)
      iex> {:ok, table} = Ankh.Protocol.HTTP3.QPACK.Table.insert(table, "content-type", "text/plain")
      iex> Ankh.Protocol.HTTP3.QPACK.Table.insert_count(table)
      1
      iex> Ankh.Protocol.HTTP3.QPACK.Table.size(table)
      byte_size("content-type") + byte_size("text/plain") + 32

      iex> Ankh.Protocol.HTTP3.QPACK.Table.insert(Ankh.Protocol.HTTP3.QPACK.Table.new(0), "x", "y")
      {:error, :too_large}

  """
  @spec insert(t(), binary(), binary()) :: {:ok, t()} | {:error, :too_large}
  def insert(%__MODULE__{max_capacity: max_capacity} = table, name, value)
      when is_binary(name) and is_binary(value) do
    entry_size = byte_size(name) + byte_size(value) + @entry_overhead

    if entry_size > max_capacity do
      {:error, :too_large}
    else
      %__MODULE__{} = table = evict_to_fit(table, max_capacity - entry_size)

      {:ok,
       %__MODULE__{
         table
         | entries: [{name, value} | table.entries],
           size: table.size + entry_size,
           insert_count: table.insert_count + 1
       }}
    end
  end

  @doc """
  Look up a dynamic table entry by its QPACK relative index.

  ## Relative indexing

  QPACK's relative index `0` always refers to the most recently inserted entry
  *at the time the header block was encoded*. The `base` argument captures that
  moment: it is the `insert_count` value used as the encoding base (i.e.
  Required Insert Count − 1, per RFC 9204 § 3.2.6).

  The absolute index of the entry is derived as:

      absolute_index = base - 1 - relative_index

  which is then mapped to a position in the newest-first `entries` list:

      list_position = insert_count - 1 - absolute_index

  Returns `{:ok, {name, value}}` when the entry exists and has not been evicted,
  or `:error` when the index falls outside the live range of the table.

  ## Examples

      iex> table = Ankh.Protocol.HTTP3.QPACK.Table.new(4096)
      iex> {:ok, table} = Ankh.Protocol.HTTP3.QPACK.Table.insert(table, "a", "1")
      iex> {:ok, table} = Ankh.Protocol.HTTP3.QPACK.Table.insert(table, "b", "2")
      iex> # insert_count is 2; use base = 2
      iex> # relative 0 → absolute 1 → "b" (newest)
      iex> Ankh.Protocol.HTTP3.QPACK.Table.lookup_relative(table, 0, 2)
      {:ok, {"b", "2"}}
      iex> # relative 1 → absolute 0 → "a" (oldest)
      iex> Ankh.Protocol.HTTP3.QPACK.Table.lookup_relative(table, 1, 2)
      {:ok, {"a", "1"}}
      iex> Ankh.Protocol.HTTP3.QPACK.Table.lookup_relative(table, 2, 2)
      :error

  """
  @spec lookup_relative(t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, {binary(), binary()}} | :error
  def lookup_relative(
        %__MODULE__{entries: entries, insert_count: insert_count},
        relative_index,
        base
      )
      when is_integer(relative_index) and relative_index >= 0 and
             is_integer(base) and base >= 0 do
    # Convert QPACK relative index + base to an absolute (0-based) insertion index.
    absolute_index = base - 1 - relative_index

    # Map absolute index to a position in the newest-first entries list.
    # Entry at list position p has absolute index (insert_count - 1 - p).
    list_pos = insert_count - 1 - absolute_index

    if absolute_index >= 0 and list_pos >= 0 and list_pos < length(entries) do
      {:ok, Enum.at(entries, list_pos)}
    else
      :error
    end
  end

  @doc """
  Return the current occupied size of the dynamic table in bytes.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc """
  Return the maximum capacity of the dynamic table in bytes.
  """
  @spec max_capacity(t()) :: non_neg_integer()
  def max_capacity(%__MODULE__{max_capacity: max_capacity}), do: max_capacity

  @doc """
  Return the total number of entries ever inserted into the table.

  This counter is monotonically increasing and is never decremented by
  evictions. It is used to derive the **Required Insert Count** for any header
  block that references dynamic table entries (RFC 9204 § 3.2.6).
  """
  @spec insert_count(t()) :: non_neg_integer()
  def insert_count(%__MODULE__{insert_count: insert_count}), do: insert_count

  @doc """
  Change the maximum capacity of the dynamic table to `new_max` bytes.

  When `new_max` is smaller than the current occupied `size`, the oldest
  entries are evicted until the table fits within the new limit. `insert_count`
  is unaffected; evictions never reset it.

  ## Examples

      iex> table = Ankh.Protocol.HTTP3.QPACK.Table.new(4096)
      iex> {:ok, table} = Ankh.Protocol.HTTP3.QPACK.Table.insert(table, "content-type", "text/plain")
      iex> table = Ankh.Protocol.HTTP3.QPACK.Table.resize(table, 0)
      iex> Ankh.Protocol.HTTP3.QPACK.Table.size(table)
      0
      iex> Ankh.Protocol.HTTP3.QPACK.Table.insert_count(table)
      1

  """
  @spec resize(t(), non_neg_integer()) :: t()
  def resize(%__MODULE__{} = table, new_max)
      when is_integer(new_max) and new_max >= 0 do
    %__MODULE__{table | max_capacity: new_max}
    |> evict_to_fit(new_max)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Evict the oldest entries (tail of the newest-first list) one at a time
  # until the occupied size is at or below `target_size`.
  #
  # When the table is already within budget, or there are no more entries to
  # drop, this is a no-op.
  @spec evict_to_fit(t(), non_neg_integer()) :: t()
  defp evict_to_fit(%__MODULE__{size: size} = table, target_size)
       when size <= target_size,
       do: table

  defp evict_to_fit(%__MODULE__{entries: []} = table, _target_size), do: table

  defp evict_to_fit(%__MODULE__{entries: entries, size: size} = table, target_size) do
    # Entries are newest-first; the oldest entry to evict is at the tail.
    {oldest_name, oldest_value} = List.last(entries)
    oldest_entry_size = byte_size(oldest_name) + byte_size(oldest_value) + @entry_overhead

    %__MODULE__{table | entries: :lists.droplast(entries), size: size - oldest_entry_size}
    |> evict_to_fit(target_size)
  end
end
