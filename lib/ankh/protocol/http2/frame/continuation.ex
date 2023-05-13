defmodule Ankh.Protocol.HTTP2.Frame.Continuation do
  @moduledoc false

  defmodule Flags do
    @moduledoc false

    @type t :: %__MODULE__{end_headers: boolean()}
    defstruct end_headers: false

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      def decode(%@for{} = flags, <<_::5, 0::1, _::2>>, _),
        do: {:ok, %{flags | end_headers: false}}

      def decode(%@for{} = flags, <<_::5, 1::1, _::2>>, _),
        do: {:ok, %{flags | end_headers: true}}

      def decode(_flags, _data, _options), do: {:error, :decode_error}

      def encode(%@for{end_headers: true}, _), do: {:ok, <<0::5, 1::1, 0::2>>}
      def encode(%@for{end_headers: false}, _), do: {:ok, <<0::5, 0::1, 0::2>>}
      def encode(_flags, _options), do: {:error, :encode_error}
    end
  end

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{hbf: binary()}
    defstruct hbf: []

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      def decode(%@for{} = payload, data, _options) when is_binary(data),
        do: {:ok, %{payload | hbf: data}}

      def decode(_payload, _options), do: {:error, :decode_error}

      def encode(%@for{hbf: hbf}, _), do: {:ok, [hbf]}
      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP2.Frame, type: 0x9, flags: Flags, payload: Payload
end
