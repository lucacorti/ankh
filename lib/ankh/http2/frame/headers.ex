defmodule Ankh.HTTP2.Frame.Headers do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.HTTP2.Frame, type: 0x1, flags: Flags, payload: Payload
end
