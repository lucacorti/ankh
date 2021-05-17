defmodule Ankh.HTTP2.Frame.WindowUpdate do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{increment: non_neg_integer()}
    defstruct increment: 0

    defimpl Ankh.HTTP2.Frame.Encodable do
      def decode(%Payload{} = payload, <<_::1, increment::31>>, _),
        do: {:ok, %{payload | increment: increment}}

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(%Payload{increment: increment}, _),
        do: {:ok, [<<0::1, increment::31>>]}

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.HTTP2.Frame, type: 0x8, payload: Payload
end
