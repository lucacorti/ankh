defmodule Ankh.Frame.Priority do
  @moduledoc false

  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x2, payload: Payload
end
