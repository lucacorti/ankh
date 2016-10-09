defmodule Ankh.Frame.PushPromise do
  @moduledoc """
  HTTP/2 PUSH_PROMISE frame struct
  """

  alias __MODULE__.{Flags, Payload}
  use Ankh.Frame, type: 0x5, flags: %Flags{}, payload: %Payload{}
end
