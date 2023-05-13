defmodule Ankh.Protocol.HTTP2.Frame.RstStream do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    alias Ankh.HTTP.Error
    alias Ankh.Protocol.HTTP2

    @type t :: %__MODULE__{error_code: Error.reason()}
    defstruct error_code: :no_error

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      alias Ankh.Protocol.HTTP2.Error

      def decode(%@for{} = payload, <<error::32>>, _),
        do: {:ok, %{payload | error_code: HTTP2.Error.decode(error)}}

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(%@for{error_code: error}, _),
        do: {:ok, [HTTP2.Error.encode(error)]}

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP2.Frame, type: 0x3, payload: Payload
end
