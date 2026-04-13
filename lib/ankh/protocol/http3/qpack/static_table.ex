defmodule Ankh.Protocol.HTTP3.QPACK.StaticTable do
  @moduledoc """
  QPACK static table as defined in RFC 9204, Appendix A.

  The static table contains 99 pre-defined header field entries (indices 0–98)
  that both encoder and decoder share without any negotiation. Using static table
  references in QPACK-encoded header blocks saves bytes on the wire by replacing
  common header name/value pairs with compact integer indices.

  Three compile-time lookup structures are derived from the raw table:

    * `@by_index`      — look up a `{name, value}` pair by its integer index.
    * `@by_name_value` — look up the index for an exact `{name, value}` match.
    * `@by_name`       — look up the lowest index that carries a given header name,
                         useful when only the name (not the value) can be matched
                         statically.

  All three maps are built at compile time, so every public function in this
  module resolves to a single map lookup at runtime.
  """

  # ---------------------------------------------------------------------------
  # Raw table — {index, name, value}, 0-based, ordered by index.
  # Source: RFC 9204, Appendix A <https://www.rfc-editor.org/rfc/rfc9204#appendix-A>
  # ---------------------------------------------------------------------------

  @table [
    {0, ":authority", ""},
    {1, ":path", "/"},
    {2, "age", "0"},
    {3, "content-disposition", ""},
    {4, "content-length", "0"},
    {5, "cookie", ""},
    {6, "date", ""},
    {7, "etag", ""},
    {8, "if-modified-since", ""},
    {9, "if-none-match", ""},
    {10, "last-modified", ""},
    {11, "link", ""},
    {12, "location", ""},
    {13, "referer", ""},
    {14, "set-cookie", ""},
    {15, ":method", "CONNECT"},
    {16, ":method", "DELETE"},
    {17, ":method", "GET"},
    {18, ":method", "HEAD"},
    {19, ":method", "OPTIONS"},
    {20, ":method", "POST"},
    {21, ":method", "PUT"},
    {22, ":scheme", "http"},
    {23, ":scheme", "https"},
    {24, ":status", "103"},
    {25, ":status", "200"},
    {26, ":status", "304"},
    {27, ":status", "404"},
    {28, ":status", "503"},
    {29, "accept", "*/*"},
    {30, "accept", "application/dns-message"},
    {31, "accept-encoding", "gzip, deflate, br"},
    {32, "accept-ranges", "bytes"},
    {33, "access-control-allow-headers", "cache-control"},
    {34, "access-control-allow-headers", "content-type"},
    {35, "access-control-allow-origin", "*"},
    {36, "cache-control", "max-age=0"},
    {37, "cache-control", "max-age=2592000"},
    {38, "cache-control", "max-age=604800"},
    {39, "cache-control", "no-cache"},
    {40, "cache-control", "no-store"},
    {41, "cache-control", "public, max-age=31536000"},
    {42, "content-encoding", "br"},
    {43, "content-encoding", "gzip"},
    {44, "content-type", "application/dns-message"},
    {45, "content-type", "application/javascript"},
    {46, "content-type", "application/json"},
    {47, "content-type", "application/x-www-form-urlencoded"},
    {48, "content-type", "image/gif"},
    {49, "content-type", "image/jpeg"},
    {50, "content-type", "image/png"},
    {51, "content-type", "text/css"},
    {52, "content-type", "text/html; charset=utf-8"},
    {53, "content-type", "text/plain"},
    {54, "content-type", "text/plain;charset=utf-8"},
    {55, "range", "bytes=0-"},
    {56, "strict-transport-security", "max-age=31536000"},
    {57, "strict-transport-security", "max-age=31536000; includesubdomains"},
    {58, "strict-transport-security", "max-age=31536000; includesubdomains; preload"},
    {59, "vary", "accept-encoding"},
    {60, "vary", "origin"},
    {61, "x-content-type-options", "nosniff"},
    {62, "x-xss-protection", "1; mode=block"},
    {63, ":status", "100"},
    {64, ":status", "204"},
    {65, ":status", "206"},
    {66, ":status", "302"},
    {67, ":status", "400"},
    {68, ":status", "403"},
    {69, ":status", "421"},
    {70, ":status", "425"},
    {71, ":status", "500"},
    {72, "accept-language", ""},
    {73, "access-control-allow-credentials", "FALSE"},
    {74, "access-control-allow-credentials", "TRUE"},
    {75, "access-control-allow-headers", "*"},
    {76, "access-control-allow-methods", "get"},
    {77, "access-control-allow-methods", "get, post, options"},
    {78, "access-control-allow-methods", "options"},
    {79, "access-control-expose-headers", "content-length"},
    {80, "access-control-request-headers", "content-type"},
    {81, "access-control-request-method", "get"},
    {82, "access-control-request-method", "post"},
    {83, "alt-svc", "clear"},
    {84, "authorization", ""},
    {85, "content-security-policy", "script-src 'none'; object-src 'none'; base-uri 'none'"},
    {86, "early-data", "1"},
    {87, "expect-ct", ""},
    {88, "forwarded", ""},
    {89, "if-range", ""},
    {90, "origin", ""},
    {91, "purpose", "prefetch"},
    {92, "server", ""},
    {93, "timing-allow-origin", "*"},
    {94, "upgrade-insecure-requests", "1"},
    {95, "user-agent", ""},
    {96, "x-forwarded-for", ""},
    {97, "x-frame-options", "deny"},
    {98, "x-frame-options", "sameorigin"}
  ]

  # ---------------------------------------------------------------------------
  # Derived compile-time lookup maps
  # ---------------------------------------------------------------------------

  # %{index => {name, value}}
  @by_index Map.new(@table, fn {index, name, value} -> {index, {name, value}} end)

  # %{{name, value} => index}
  # Iterating in ascending index order and using Map.put_new/3 ensures that
  # when multiple entries share the same {name, value} pair, the lowest index
  # (i.e. the first occurrence) is retained.
  @by_name_value Enum.reduce(@table, %{}, fn {index, name, value}, acc ->
                   Map.put_new(acc, {name, value}, index)
                 end)

  # %{name => index}
  # Same strategy: first (lowest-index) occurrence wins per name.
  @by_name Enum.reduce(@table, %{}, fn {index, name, _value}, acc ->
             Map.put_new(acc, name, index)
           end)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Look up a static table entry by its zero-based index.

  Returns `{:ok, {name, value}}` when the index exists in the static table,
  or `:error` when it is out of range.

  ## Examples

      iex> Ankh.Protocol.HTTP3.QPACK.StaticTable.lookup(0)
      {:ok, {":authority", ""}}

      iex> Ankh.Protocol.HTTP3.QPACK.StaticTable.lookup(17)
      {:ok, {":method", "GET"}}

      iex> Ankh.Protocol.HTTP3.QPACK.StaticTable.lookup(99)
      :error

  """
  @spec lookup(non_neg_integer()) :: {:ok, {binary(), binary()}} | :error
  def lookup(index) when is_integer(index) and index >= 0 do
    case Map.fetch(@by_index, index) do
      {:ok, _} = ok -> ok
      :error -> :error
    end
  end

  @doc """
  Find the static table index for an exact header name + value match.

  When the same `{name, value}` pair appears at multiple indices (which does
  not happen in the current RFC 9204 static table, but is guarded against),
  the lowest index is returned.

  Returns `{:ok, index}` on a match, or `:error` when no entry matches.

  ## Examples

      iex> Ankh.Protocol.HTTP3.QPACK.StaticTable.find_name_value(":method", "GET")
      {:ok, 17}

      iex> Ankh.Protocol.HTTP3.QPACK.StaticTable.find_name_value(":method", "PATCH")
      :error

  """
  @spec find_name_value(binary(), binary()) :: {:ok, non_neg_integer()} | :error
  def find_name_value(name, value) when is_binary(name) and is_binary(value) do
    Map.fetch(@by_name_value, {name, value})
  end

  @doc """
  Find the lowest static table index that contains the given header name,
  regardless of its associated value.

  This is useful during encoding when only the name (not the value) matches a
  static table entry, allowing a name-reference with a literal value instead of
  a full indexed representation.

  Returns `{:ok, index}` when the name exists in the static table, or `:error`
  when no entry with that name is present.

  ## Examples

      iex> Ankh.Protocol.HTTP3.QPACK.StaticTable.find_name(":method")
      {:ok, 15}

      iex> Ankh.Protocol.HTTP3.QPACK.StaticTable.find_name("x-custom-header")
      :error

  """
  @spec find_name(binary()) :: {:ok, non_neg_integer()} | :error
  def find_name(name) when is_binary(name) do
    Map.fetch(@by_name, name)
  end
end
