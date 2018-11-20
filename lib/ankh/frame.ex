defmodule Ankh.Frame do
  @moduledoc """
  HTTP/2 frame struct

  The __using__ macro injects the frame struct needed by the
  `Ankh.Frame.Encoder` protocol.
  """

  @doc """
  Injects the frame struct in a module.

  - type: HTTP/2 frame type code
  - flags: frame flags struct or nil for no flags
  - payload: frame payload struct or nil for no payload
  """
  @spec __using__(type: Integer.t(), flags: struct, payload: struct) :: Macro.t()
  defmacro __using__(args) do
    with {:ok, type} <- Keyword.fetch(args, :type),
         flags <- Keyword.get(args, :flags),
         payload <- Keyword.get(args, :payload) do
      quote bind_quoted: [type: type, flags: flags, payload: payload] do
        @typedoc """
        - length: payload length in bytes
        - flags: data type implementing `Ankh.Frame.Flags`
        - stream_id: Stream ID of the frame
        - payload: data type implementing `Ankh.Frame.Payload`
        """
        @type t :: %__MODULE__{
                length: Integer.t(),
                stream_id: Integer.t(),
                flags: Flags.t(),
                payload: Payload.t()
              }

        defstruct length: 0, type: type, stream_id: 0, flags: flags, payload: payload
      end
    else
      :error ->
        raise "Missing type code: You must provide a type code for the frame"
    end
  end
end
