defmodule Ankh.Frame.Priority.Payload do
  @moduledoc false

  @type t :: %__MODULE__{exclusive: boolean, stream_dependency: Integer.t(), weight: Integer.t()}
  defstruct exclusive: false, stream_dependency: 0, weight: 0
end

defimpl Ankh.Frame.Payload, for: Ankh.Frame.Priority.Payload do
  import Ankh.Frame.Utils

  def encode!(%{exclusive: ex, stream_dependency: sd, weight: wh}, _) do
    [<<bool_to_int!(ex)::1, sd::31, wh::8>>]
  end

  def decode!(payload, <<ex::1, sd::31, wh::8>>, _) do
    %{payload | exclusive: int_to_bool!(ex), stream_dependency: sd, weight: wh}
  end
end
