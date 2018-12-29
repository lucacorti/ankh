defmodule Ankh.Frame.PushPromise do
  @moduledoc false

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x5, flags: Flags, payload: Payload
end
