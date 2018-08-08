defmodule Ankh.Frame.Data do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x0, flags: %Flags{}, payload: %Payload{}
end
