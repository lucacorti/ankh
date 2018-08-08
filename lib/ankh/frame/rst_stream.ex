defmodule Ankh.Frame.RstStream do
  @moduledoc false

  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x3, payload: %Payload{}
end
