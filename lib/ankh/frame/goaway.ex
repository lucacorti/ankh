defmodule Ankh.Frame.Goaway do
  @moduledoc """
  GOAWAY frame struct
  """
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x7, flags: nil, payload: %Payload{}
end
