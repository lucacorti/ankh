defmodule Ankh.Frame.Data do
  @moduledoc """
  HTTP/2 DATA frame struct
  """

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x0, flags: %Flags{}, payload: %Payload{}
end
