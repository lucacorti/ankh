defmodule Ankh.Protocol.HTTP2.Frame.Priority do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    alias Ankh.Protocol.HTTP2.Stream, as: HTTP2Stream

    @type t :: %__MODULE__{
            exclusive: boolean(),
            stream_dependency: HTTP2Stream.id(),
            weight: non_neg_integer()
          }
    defstruct exclusive: false, stream_dependency: 0, weight: 0

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      def decode(%@for{} = payload, <<1::1, sd::31, wh::8>>, _) do
        {:ok, %{payload | exclusive: true, stream_dependency: sd, weight: wh}}
      end

      def decode(%@for{} = payload, <<0::1, sd::31, wh::8>>, _) do
        {:ok, %{payload | exclusive: false, stream_dependency: sd, weight: wh}}
      end

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(%@for{exclusive: true, stream_dependency: sd, weight: wh}, _) do
        {:ok, [<<1::1, sd::31, wh::8>>]}
      end

      def encode(%@for{exclusive: false, stream_dependency: sd, weight: wh}, _) do
        {:ok, [<<0::1, sd::31, wh::8>>]}
      end

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP2.Frame, type: 0x2, payload: Payload
end
