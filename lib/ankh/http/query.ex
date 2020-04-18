defmodule Ankh.HTTP.Query do
  @moduledoc """
  Recursive HTTP query encode/decode to/from x-www-urlencoded form

  This code was taken and adapted from Plug `Plug.Conn.Query` and `Plug.Conn.Utils` which
  are distributed under the [Apache 2.0 license](http://www.apache.org/licenses/LICENSE-2.0).
  """

  @type t :: map()
  @type query :: binary()

  defmodule InvalidQueryError do
    defexception [:message]
  end

  @doc """
  Decodes the given binary.
  The binary is assumed to be encoded in "x-www-form-urlencoded" format.
  The format is decoded and then validated for proper UTF-8 encoding.
  """
  @spec decode(query) :: t()
  def decode(string)

  def decode(""), do: %{}

  def decode(string) do
    string
    |> :binary.split("&", [:global])
    |> Enum.reverse()
    |> Enum.reduce(%{}, &decode_www_pair(&1, &2))
  end

  defp decode_www_pair("", acc), do: acc

  defp decode_www_pair(binary, acc) do
    current =
      case :binary.split(binary, "=") do
        [key, value] ->
          {decode_www_form(key), decode_www_form(value)}

        [key] ->
          {decode_www_form(key), nil}
      end

    decode_pair(current, acc)
  end

  defp decode_www_form(value) do
    URI.decode_www_form(value)
  rescue
    ArgumentError ->
      raise InvalidQueryError, "invalid urlencoded params, got #{value}"
  else
    binary ->
      validate_utf8!(binary, InvalidQueryError, "urlencoded params")
      binary
  end

  defp decode_pair({key, value}, acc) do
    if key != "" and :binary.last(key) == ?] do
      # Remove trailing ]
      subkey = :binary.part(key, 0, byte_size(key) - 1)

      # Split the first [ then we will split on remaining ][.
      #
      #     users[address][street #=> [ "users", "address][street" ]
      #
      assign_split(:binary.split(subkey, "["), value, acc, :binary.compile_pattern("]["))
    else
      assign_map(acc, key, value)
    end
  end

  defp assign_split(["", rest], value, acc, pattern) do
    parts = :binary.split(rest, pattern)

    case acc do
      [_ | _] -> [assign_split(parts, value, :none, pattern) | acc]
      :none -> [assign_split(parts, value, :none, pattern)]
      _ -> acc
    end
  end

  defp assign_split([key, rest], value, acc, pattern) do
    parts = :binary.split(rest, pattern)

    case acc do
      %{^key => current} ->
        Map.put(acc, key, assign_split(parts, value, current, pattern))

      %{} ->
        Map.put(acc, key, assign_split(parts, value, :none, pattern))

      _ ->
        %{key => assign_split(parts, value, :none, pattern)}
    end
  end

  defp assign_split([""], nil, acc, _pattern) do
    case acc do
      [_ | _] -> acc
      _ -> []
    end
  end

  defp assign_split([""], value, acc, _pattern) do
    case acc do
      [_ | _] -> [value | acc]
      :none -> [value]
      _ -> acc
    end
  end

  defp assign_split([key], value, acc, _pattern) do
    assign_map(acc, key, value)
  end

  defp assign_map(acc, key, value) do
    case acc do
      %{^key => _} -> acc
      %{} -> Map.put(acc, key, value)
      _ -> %{key => value}
    end
  end

  @doc """
  Encodes the given map or list of stuples.
  """
  @spec encode(t()) :: query()
  def encode(map) do
    ""
    |> encode_pair(map, &to_string/1)
    |> IO.iodata_to_binary()
  end

  # covers structs
  defp encode_pair(field, %{__struct__: struct} = map, encoder) when is_atom(struct) do
    [field, ?= | encode_value(map, encoder)]
  end

  # covers maps
  defp encode_pair(parent_field, %{} = map, encoder) do
    encode_kv(map, parent_field, encoder)
  end

  # covers keyword lists
  defp encode_pair(parent_field, list, encoder) when is_list(list) and is_tuple(hd(list)) do
    encode_kv(Enum.uniq_by(list, &elem(&1, 0)), parent_field, encoder)
  end

  # covers non-keyword lists
  defp encode_pair(parent_field, list, encoder) when is_list(list) do
    mapper = fn
      value when is_map(value) and map_size(value) != 1 ->
        raise ArgumentError,
              "cannot encode maps inside lists when the map has 0 or more than 1 elements, " <>
                "got: #{inspect(value)}"

      value ->
        [?&, encode_pair(parent_field <> "[]", value, encoder)]
    end

    list
    |> Enum.flat_map(mapper)
    |> prune()
  end

  # covers nil
  defp encode_pair(field, nil, _encoder) do
    [field, ?=]
  end

  # encoder fallback
  defp encode_pair(field, value, encoder) do
    [field, ?= | encode_value(value, encoder)]
  end

  defp encode_kv(kv, parent_field, encoder) do
    mapper = fn
      {_, value} when value in [%{}, []] ->
        []

      {field, value} ->
        field =
          if parent_field == "" do
            encode_key(field)
          else
            parent_field <> "[" <> encode_key(field) <> "]"
          end

        [?&, encode_pair(field, value, encoder)]
    end

    kv
    |> Enum.flat_map(mapper)
    |> prune()
  end

  defp encode_key(item) do
    item |> to_string |> URI.encode_www_form()
  end

  defp encode_value(item, encoder) do
    item |> encoder.() |> URI.encode_www_form()
  end

  defp prune([?& | t]), do: t
  defp prune([]), do: []

  defp validate_utf8!(binary, exception, context)

  defp validate_utf8!(<<_::utf8, t::binary>>, exception, context) do
    validate_utf8!(t, exception, context)
  end

  defp validate_utf8!(<<h, _::binary>>, exception, context) do
    raise exception, "invalid UTF-8 on #{context}, got byte #{h}"
  end

  defp validate_utf8!(<<>>, _exception, _context), do: :ok
end
