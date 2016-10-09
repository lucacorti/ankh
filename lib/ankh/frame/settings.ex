defmodule Ankh.Frame.Settings do
  @moduledoc """
  HTTP/2 SETTINGS frame struct
  """

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x4, flags: %Flags{}, payload: %Payload{}
end
