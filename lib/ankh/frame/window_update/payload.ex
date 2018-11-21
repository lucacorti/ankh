defmodule Ankh.Frame.WindowUpdate.Payload do
  @moduledoc false

  @type t :: %__MODULE__{window_size_increment: Integer.t()}
  defstruct window_size_increment: 0
end

defimpl Ankh.Frame.Payload, for: Ankh.Frame.WindowUpdate.Payload do
  def decode!(payload, <<_::1, window_size_increment::31>>, _) do
    %{payload | window_size_increment: window_size_increment}
  end

  def encode!(%{window_size_increment: wsi}, _), do: [<<0::1, wsi::31>>]
end
