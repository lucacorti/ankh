defmodule Ankh.Frame.Headers do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x1, flags: %Flags{}, payload: %Payload{}
end
