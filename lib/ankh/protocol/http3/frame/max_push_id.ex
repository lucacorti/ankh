defmodule Ankh.Protocol.HTTP3.Frame.MaxPushId do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{push_id: non_neg_integer()}
    defstruct push_id: 0

    defimpl Ankh.Protocol.HTTP3.Frame.Encodable do
      alias Ankh.Protocol.HTTP3.Frame

      def decode(%@for{} = payload, <<0::2, n::6, _::binary>>),
        do: {:ok, %{payload | push_id: n}}

      def decode(%@for{} = payload, <<1::2, n::14, _::binary>>),
        do: {:ok, %{payload | push_id: n}}

      def decode(%@for{} = payload, <<2::2, n::30, _::binary>>),
        do: {:ok, %{payload | push_id: n}}

      def decode(%@for{} = payload, <<3::2, n::62, _::binary>>),
        do: {:ok, %{payload | push_id: n}}

      def decode(_payload, _binary), do: {:error, :decode_error}

      def encode(%@for{push_id: id}), do: {:ok, Frame.encode_vli(id)}
      def encode(_payload), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP3.Frame, type: 0xD, payload: Payload
end
