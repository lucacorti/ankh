defmodule Ankh.Frame.Headers do
  @moduledoc """
  HEADERS frame struct
  """
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x1, flags: %Flags{}, payload: %Payload{}
end
