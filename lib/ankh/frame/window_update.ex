defmodule Ankh.Frame.WindowUpdate do
  @moduledoc false

  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x8, payload: Payload
end
