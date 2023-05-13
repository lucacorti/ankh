defmodule Ankh.Protocol.HTTP2.Frame.GoAway do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    alias Ankh.HTTP.Error
    alias Ankh.Protocol.HTTP2

    @type t :: %__MODULE__{
            last_stream_id: HTTP2.Stream.id(),
            error_code: Error.reason(),
            data: binary()
          }
    defstruct last_stream_id: nil, error_code: nil, data: <<>>

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      alias Ankh.Protocol.HTTP2.Error

      def decode(%@for{} = payload, <<_::1, lsid::31, error::32>>, _),
        do: {:ok, %{payload | last_stream_id: lsid, error_code: HTTP2.Error.decode(error)}}

      def decode(%@for{} = payload, <<_::1, lsid::31, error::32, data::binary>>, _),
        do:
          {:ok,
           %{payload | last_stream_id: lsid, error_code: HTTP2.Error.decode(error), data: data}}

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(%@for{last_stream_id: lsid, error_code: error, data: data}, _),
        do: {:ok, [<<0::1, lsid::31>>, HTTP2.Error.encode(error), data]}

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP2.Frame, type: 0x7, payload: Payload
end
