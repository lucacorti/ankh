defmodule Ankh.HTTP2.Frame.GoAway do
  @moduledoc false

  alias __MODULE__.Payload
  use Ankh.HTTP2.Frame, type: 0x7, payload: Payload
end
