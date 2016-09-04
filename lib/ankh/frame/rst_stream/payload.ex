defmodule Ankh.Frame.RstStream.Payload do
  defstruct [error_code: nil]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.RstStream.Payload do
  alias Ankh.Frame.RstStream.Payload
  alias Ankh.Frame.{Encoder, Error}

  def decode!(struct, <<error::32>>, _) do
    %{struct | error_code: Encoder.decode!(%Error{}, error, [])}
  end

  def encode!(%Payload{error_code: error}, _), do: Encoder.encode!(error, [])
end
