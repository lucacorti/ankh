defmodule Ankh.HTTP2.Frame.Priority do
  @moduledoc false

  alias __MODULE__.Payload
  use Ankh.HTTP2.Frame, type: 0x2, payload: Payload
end
