defmodule Ankh.Frame.Ping.Payload do
  @moduledoc """
  PING frame payload
  """

  @type t :: %__MODULE__{data: binary}
  defstruct [data: <<>>]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Ping.Payload do
  alias Ankh.Frame.Ping.Payload

  def encode!(%Payload{data: data}, _) when is_binary(data), do: data

  def decode!(struct, data, _) when is_binary(data), do: %{struct | data: data}
end
