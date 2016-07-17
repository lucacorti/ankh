defmodule Http2.Frame.WindowUpdate.Payload do
  defstruct [window_size_increment: nil]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.WindowUpdate.Payload do
  alias Http2.Frame.WindowUpdate.Payload

  def decode!(struct, <<_::1, window_size_increment::31>>, _) do
    %{struct | window_size_increment: window_size_increment}
  end

  def encode!(%Payload{window_size_increment: wsi}, _), do: <<0::1, wsi::31>>
end
