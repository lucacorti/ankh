defmodule Ankh.Frame.RstStream.Payload do
  @moduledoc false
  alias Ankh.Error

  @type t :: %__MODULE__{error_code: Error.t()}
  defstruct error_code: nil
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.RstStream.Payload do
  alias Ankh.Error

  def decode!(payload, <<error::32>>, _) do
    %{payload | error_code: Error.decode!(error)}
  end

  def encode!(%{error_code: error}, _), do: [Error.encode!(error)]
end
