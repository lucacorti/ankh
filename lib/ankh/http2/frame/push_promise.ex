defmodule Ankh.HTTP2.Frame.PushPromise do
  @moduledoc false

  defmodule Flags do
    @moduledoc false

    @type t :: %__MODULE__{end_headers: boolean(), padded: boolean()}
    defstruct end_headers: false, padded: false

    defimpl Ankh.HTTP2.Frame.Encodable do
      def decode(%Flags{} = flags, <<_::4, 1::1, 1::1, _::2>>, _) do
        {:ok, %{flags | end_headers: true, padded: true}}
      end

      def decode(%Flags{} = flags, <<_::4, 1::1, 0::1, _::2>>, _) do
        {:ok, %{flags | end_headers: false, padded: true}}
      end

      def decode(%Flags{} = flags, <<_::4, 0::1, 1::1, _::2>>, _) do
        {:ok, %{flags | end_headers: true, padded: false}}
      end

      def decode(%Flags{} = flags, <<_::4, 0::1, 0::1, _::2>>, _) do
        {:ok, %{flags | end_headers: false, padded: false}}
      end

      def decode(_flags, _data, _options), do: {:error, :decode_error}

      def encode(%Flags{end_headers: true, padded: true}, _) do
        {:ok, <<0::4, 1::1, 1::1, 0::2>>}
      end

      def encode(%Flags{end_headers: true, padded: false}, _) do
        {:ok, <<0::4, 0::1, 1::1, 0::2>>}
      end

      def encode(%Flags{end_headers: false, padded: true}, _) do
        {:ok, <<0::4, 1::1, 0::1, 0::2>>}
      end

      def encode(%Flags{end_headers: false, padded: false}, _) do
        {:ok, <<0::4, 0::1, 0::1, 0::2>>}
      end

      def encode(_flags, _options), do: {:error, :encode_error}
    end
  end

  defmodule Payload do
    @moduledoc false

    alias Ankh.HTTP2.Stream, as: HTTP2Stream

    @type t :: %__MODULE__{
            pad_length: non_neg_integer(),
            promised_stream_id: HTTP2Stream.id(),
            hbf: binary()
          }
    defstruct pad_length: 0, promised_stream_id: 0, hbf: []

    defimpl Ankh.HTTP2.Frame.Encodable do
      alias Ankh.HTTP2.Frame.PushPromise.{Flags, Payload}

      def decode(
            %Payload{} = payload,
            <<pl::8, _::1, psi::31, data::binary>>,
            flags: %Flags{padded: true}
          ) do
        {:ok,
         %{
           payload
           | pad_length: pl,
             promised_stream_id: psi,
             hbf: binary_part(data, 0, byte_size(data) - pl)
         }}
      end

      def decode(
            %Payload{} = payload,
            <<_::8, _::1, psi::31, hbf::binary>>,
            flags: %Flags{padded: false}
          ) do
        {:ok, %{payload | promised_stream_id: psi, hbf: hbf}}
      end

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(
            %Payload{pad_length: pad_length, promised_stream_id: psi, hbf: hbf},
            flags: %Flags{padded: true}
          ) do
        {:ok, [<<pad_length::8, 0::1, psi::31>>, hbf, :binary.copy(<<0>>, pad_length)]}
      end

      def encode(%Payload{promised_stream_id: psi, hbf: hbf}, flags: %Flags{padded: false}) do
        {:ok, [<<0::1, psi::31>>, hbf]}
      end

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.HTTP2.Frame, type: 0x5, flags: Flags, payload: Payload
end
