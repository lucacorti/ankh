defmodule Ankh.HTTP2.Frame.PushPromise do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.HTTP2.Frame, type: 0x5, flags: Flags, payload: Payload
end
