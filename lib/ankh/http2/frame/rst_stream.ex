defmodule Ankh.HTTP2.Frame.RstStream do
  @moduledoc false

  defmodule Payload do
    @moduledoc false
    alias Ankh.HTTP2.Error

    @type t :: %__MODULE__{error_code: Error.t()}
    defstruct error_code: :no_error

    defimpl Ankh.HTTP2.Frame.Encodable do
      alias Ankh.HTTP2.Error

      def decode(%Payload{} = payload, <<error::32>>, _),
        do: {:ok, %{payload | error_code: Error.decode(error)}}

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(%Payload{error_code: error}, _),
        do: {:ok, [Error.encode(error)]}

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.HTTP2.Frame, type: 0x3, payload: Payload
end
