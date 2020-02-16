defmodule Ankh.HTTP2.Frame.RstStream do
  @moduledoc false

  alias __MODULE__.Payload
  use Ankh.HTTP2.Frame, type: 0x3, payload: Payload
end
