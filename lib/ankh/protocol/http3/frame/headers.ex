defmodule Ankh.Protocol.HTTP3.Frame.Headers do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{hbf: binary()}
    defstruct hbf: <<>>

    defimpl Ankh.Protocol.HTTP3.Frame.Encodable do
      def decode(%@for{} = payload, binary) when is_binary(binary),
        do: {:ok, %{payload | hbf: binary}}

      def decode(_payload, _binary), do: {:error, :decode_error}

      def encode(%@for{hbf: hbf}), do: {:ok, hbf}
      def encode(_payload), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP3.Frame, type: 0x1, payload: Payload
end
