defmodule Ankh.HTTP2.Frame.Settings do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.HTTP2.Frame, type: 0x4, flags: Flags, payload: Payload
end
