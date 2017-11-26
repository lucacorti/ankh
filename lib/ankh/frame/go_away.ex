defmodule Ankh.Frame.GoAway do
  @moduledoc """
  GOAWAY frame struct
  """
  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x7, payload: %Payload{}
end
