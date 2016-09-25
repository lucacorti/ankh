defmodule Ankh.Frame.RstStream.Payload do
  @moduledoc """
  RST_STREAM frame payload
  """

  @type t :: %__MODULE__{error_code: Ank.Frame.Error.t}
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
