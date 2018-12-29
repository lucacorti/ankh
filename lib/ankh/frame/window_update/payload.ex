defmodule Ankh.Frame.WindowUpdate.Payload do
  @moduledoc false

  @type t :: %__MODULE__{window_size_increment: integer}
  defstruct window_size_increment: 0
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.WindowUpdate.Payload do
  def decode(payload, <<_::1, window_size_increment::31>>, _) do
    {:ok, %{payload | window_size_increment: window_size_increment}}
  end
  def decode(_payload, _data, _options), do: {:error, :decode_error}

  def encode(%{window_size_increment: wsi}, _), do: {:ok, [<<0::1, wsi::31>>]}
  def encode(_payload, _options), do: {:error, :encode_error}
end
