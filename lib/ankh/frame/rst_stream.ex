defmodule Ankh.Frame.RstStream do
  @moduledoc """
  RST_STREAM frame struct
  """

  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x3, payload: %Payload{}
end
