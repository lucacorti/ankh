defmodule Ankh.HTTP2.Frame.WindowUpdate do
  @moduledoc false

  alias __MODULE__.Payload
  use Ankh.HTTP2.Frame, type: 0x8, payload: Payload
end
