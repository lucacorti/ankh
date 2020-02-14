defmodule Ankh.HTTP2.Frame.Ping do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.HTTP2.Frame, type: 0x6, flags: Flags, payload: Payload
end
