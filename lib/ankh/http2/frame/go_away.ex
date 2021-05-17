defmodule Ankh.HTTP2.Frame.GoAway do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    alias Ankh.HTTP2.Error
    alias Ankh.HTTP2.Stream, as: HTTP2Stream

    @type t :: %__MODULE__{
            last_stream_id: HTTP2Stream.id(),
            error_code: Error.t(),
            data: binary()
          }
    defstruct last_stream_id: nil, error_code: nil, data: <<>>

    defimpl Ankh.HTTP2.Frame.Encodable do
      alias Ankh.HTTP2.Error

      def decode(%Payload{} = payload, <<_::1, lsid::31, error::32>>, _),
        do: {:ok, %{payload | last_stream_id: lsid, error_code: Error.decode(error)}}

      def decode(%Payload{} = payload, <<_::1, lsid::31, error::32, data::binary>>, _),
        do:
          {:ok, %{payload | last_stream_id: lsid, error_code: Error.decode(error), data: data}}

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(%Payload{last_stream_id: lsid, error_code: error, data: data}, _),
        do: {:ok, [<<0::1, lsid::31>>, Error.encode(error), data]}

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.HTTP2.Frame, type: 0x7, payload: Payload
end
