defmodule Ankh.Frame.Continuation do
  @moduledoc """
  HTTP/2 CONTINUATION frame struct
  """

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x9, flags: %Flags{}, payload: %Payload{}
end
