defmodule Ankh.Frame.Settings do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x4, flags: %Flags{}, payload: %Payload{}
end
