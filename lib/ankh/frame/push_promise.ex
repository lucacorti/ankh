defmodule Ankh.Frame.PushPromise do
  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x5, flags: %Flags{}, payload: %Payload{}
end
