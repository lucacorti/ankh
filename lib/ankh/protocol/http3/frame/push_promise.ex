defmodule Ankh.Protocol.HTTP3.Frame.PushPromise do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{push_id: non_neg_integer(), hbf: binary()}
    defstruct push_id: 0, hbf: <<>>

    defimpl Ankh.Protocol.HTTP3.Frame.Encodable do
      alias Ankh.Protocol.HTTP3.Frame

      def decode(%@for{} = payload, <<0::2, id::6, hbf::binary>>),
        do: {:ok, %{payload | push_id: id, hbf: hbf}}

      def decode(%@for{} = payload, <<1::2, id::14, hbf::binary>>),
        do: {:ok, %{payload | push_id: id, hbf: hbf}}

      def decode(%@for{} = payload, <<2::2, id::30, hbf::binary>>),
        do: {:ok, %{payload | push_id: id, hbf: hbf}}

      def decode(%@for{} = payload, <<3::2, id::62, hbf::binary>>),
        do: {:ok, %{payload | push_id: id, hbf: hbf}}

      def decode(_payload, _binary), do: {:error, :decode_error}

      def encode(%@for{push_id: id, hbf: hbf}),
        do: {:ok, [Frame.encode_vli(id), hbf]}

      def encode(_payload), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP3.Frame, type: 0x5, payload: Payload
end
