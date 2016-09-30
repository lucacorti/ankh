defmodule Ankh.Frame.RstStream.Payload do
  @moduledoc """
  RST_STREAM frame payload
  """

  @type t :: %__MODULE__{error_code: Ankh.Frame.Error.t}
  defstruct [error_code: nil]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.RstStream.Payload do
  alias Ankh.Frame.Error

  def decode!(struct, <<error::32>>, _) do
    %{struct | error_code: Error.decode!(error)}
  end

  def encode!(%{error_code: error}, _), do: Error.encode!(error)
end
