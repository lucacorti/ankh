defmodule Ankh.Frame do
  @moduledoc """
  HTTP/2 frame struct

  The __using__ macro injects the frame struct needed by the
  `Ankh.Frame.Encoder` protocol.
  """

  defmacro __using__(type: type, flags: flags, payload: payload) do
    unless is_integer(type) do
      raise CompileError, "Frame type must be Integer.t"
    end

    quote do
      alias Ankh.Frame.Encoder

      @typedoc """
      - length: payload length in bytes
      - flags: `Ankh.Frame.Flags` conforming struct
      - stream_id: Stream ID of the frame
      - payload: `Ankh.Frame.Payload` conforming struct
      """
      @type t :: %__MODULE__{length: Integer.t, stream_id: Integer.t,
      flags: unquote(flags), payload: unquote(payload)}
      defstruct [length: 0, type: unquote(type), stream_id: 0,
                 flags: unquote(flags), payload: unquote(payload)]
    end
  end
end
