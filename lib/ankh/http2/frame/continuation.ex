defmodule Ankh.HTTP2.Frame.Continuation do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.HTTP2.Frame, type: 0x9, flags: Flags, payload: Payload
end
