defmodule Ankh.HTTP2.Frame.Data do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.HTTP2.Frame, type: 0x0, flags: Flags, payload: Payload
end
