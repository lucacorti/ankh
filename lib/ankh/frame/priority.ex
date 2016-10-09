defmodule Ankh.Frame.Priority do
  @moduledoc """
  HTTP/2 PRIORITY frame struct
  """

  alias __MODULE__.Payload
  use Ankh.Frame, type: 0x5, flags: nil, payload: %Payload{}
end
