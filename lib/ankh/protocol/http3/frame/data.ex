defmodule Ankh.Protocol.HTTP3.Frame.Data do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{data: binary()}
    defstruct data: <<>>

    defimpl Ankh.Protocol.HTTP3.Frame.Encodable do
      def decode(%@for{} = payload, binary) when is_binary(binary),
        do: {:ok, %{payload | data: binary}}

      def decode(_payload, _binary), do: {:error, :decode_error}

      def encode(%@for{data: data}), do: {:ok, data}
      def encode(_payload), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP3.Frame, type: 0x0, payload: Payload
end
