defmodule Ankh.Frame.WindowUpdate do
  @moduledoc """
  WINDOW_UPDATE frame struct
  """

  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x8, flags: nil, payload: %Payload{}
end
