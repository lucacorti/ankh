defmodule Ankh.Protocol.HTTP3.Frame.Settings do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    @type setting :: {non_neg_integer(), non_neg_integer()}
    @type t :: %__MODULE__{settings: [setting()]}
    defstruct settings: []

    defimpl Ankh.Protocol.HTTP3.Frame.Encodable do
      alias Ankh.Protocol.HTTP3.Frame

      def decode(%@for{} = payload, binary) when is_binary(binary) do
        case do_decode(binary, []) do
          {:ok, pairs} -> {:ok, %{payload | settings: pairs}}
          error -> error
        end
      end

      def decode(_payload, _binary), do: {:error, :decode_error}

      defp do_decode(<<>>, acc), do: {:ok, Enum.reverse(acc)}

      defp do_decode(<<0::2, id::6, rest::binary>>, acc),
        do: do_decode_value(id, rest, acc)

      defp do_decode(<<1::2, id::14, rest::binary>>, acc),
        do: do_decode_value(id, rest, acc)

      defp do_decode(<<2::2, id::30, rest::binary>>, acc),
        do: do_decode_value(id, rest, acc)

      defp do_decode(<<3::2, id::62, rest::binary>>, acc),
        do: do_decode_value(id, rest, acc)

      defp do_decode(_, _acc), do: {:error, :decode_error}

      defp do_decode_value(id, <<0::2, v::6, rest::binary>>, acc),
        do: do_decode(rest, [{id, v} | acc])

      defp do_decode_value(id, <<1::2, v::14, rest::binary>>, acc),
        do: do_decode(rest, [{id, v} | acc])

      defp do_decode_value(id, <<2::2, v::30, rest::binary>>, acc),
        do: do_decode(rest, [{id, v} | acc])

      defp do_decode_value(id, <<3::2, v::62, rest::binary>>, acc),
        do: do_decode(rest, [{id, v} | acc])

      defp do_decode_value(_id, _rest, _acc), do: {:error, :decode_error}

      def encode(%@for{settings: settings}) do
        {:ok,
         Enum.map(settings, fn {id, value} ->
           [Frame.encode_vli(id), Frame.encode_vli(value)]
         end)}
      end

      def encode(_payload), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP3.Frame, type: 0x4, payload: Payload
end
