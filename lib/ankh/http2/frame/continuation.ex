defmodule Ankh.HTTP2.Frame.Continuation do
  @moduledoc false

  defmodule Flags do
    @moduledoc false

    @type t :: %__MODULE__{end_headers: boolean}
    defstruct end_headers: false
  end

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{hbf: binary}
    defstruct hbf: []
  end

  alias __MODULE__.{Flags, Payload}
  use Ankh.HTTP2.Frame, type: 0x9, flags: Flags, payload: Payload
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Continuation.Flags do
  def decode(flags, <<_::5, 0::1, _::2>>, _) do
    {:ok, %{flags | end_headers: false}}
  end

  def decode(flags, <<_::5, 1::1, _::2>>, _) do
    {:ok, %{flags | end_headers: true}}
  end

  def decode(_flags, _data, _options), do: {:error, :decode_error}

  def encode(%{end_headers: true}, _) do
    {:ok, <<0::5, 1::1, 0::2>>}
  end

  def encode(%{end_headers: false}, _) do
    {:ok, <<0::5, 0::1, 0::2>>}
  end

  def encode(_flags, _options), do: {:error, :encode_error}
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Continuation.Payload do
  def decode(payload, data, _) when is_binary(data), do: {:ok, %{payload | hbf: data}}
  def decode(_payload, _options), do: {:error, :decode_error}

  def encode(%{hbf: hbf}, _), do: {:ok, [hbf]}
  def encode(_payload, _options), do: {:error, :encode_error}
end
