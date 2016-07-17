defmodule Http2.Frame.RstStream.Payload do
  defstruct [error_code: nil]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.RstStream.Payload do
  alias Http2.Frame.RstStream.Payload
  alias Http2.Frame.{Encoder, Error}

  def decode!(struct, <<error::32>>, _) do
    %{struct | error_code: Encoder.decode!(%Error{}, error, [])}
  end

  def encode!(%Payload{error_code: error}, _), do: Encoder.encode!(error, [])
end
