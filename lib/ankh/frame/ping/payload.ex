defmodule Ankh.Frame.Ping.Payload do
  @moduledoc """
  PING frame payload
  """

  @type t :: %__MODULE__{data: binary}
  defstruct [data: <<>>]
end

defimpl Ankh.Frame.Payload, for: Ankh.Frame.Ping.Payload do
  def encode!(%{data: data}, _) when is_binary(data), do: data
  def decode!(struct, data, _) when is_binary(data), do: %{struct | data: data}
end
