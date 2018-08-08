defmodule Ankh.Frame.GoAway do
  @moduledoc false

  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x7, payload: %Payload{}
end
