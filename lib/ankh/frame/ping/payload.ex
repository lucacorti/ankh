defmodule Ankh.Frame.Ping.Payload do
  @moduledoc false

  @type t :: %__MODULE__{data: binary}
  defstruct data: <<>>
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.Ping.Payload do
  def encode!(%{data: data}, _) when is_binary(data), do: [data]
  def decode!(payload, data, _) when is_binary(data), do: %{payload | data: data}
end
