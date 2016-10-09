defmodule Ankh.Frame.Ping do
  @moduledoc """
  HTTP/2 PING frame struct
  """

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x6, flags: %Flags{}, payload: %Payload{}
end
