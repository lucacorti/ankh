defprotocol Ankh.Frame.Encoder do
  @moduledoc """
  Protocol for encoding/decoding HTTP/2 frames from to binary
  """

  @typedoc """
  Struct conforming to the `Ankh.Frame.Encoder` protocol
  """
  @type t :: struct
  @fallback_to_any true

  @doc """
  Decodes a binary into a conforming struct

  Parameters:
    - struct: struct conforming to the `Ank.Frame.Encoder` protocol
    - binary: data to decode into the struct
    - options: options to pass as context to the decoding function
  """
  @spec decode!(t, binary, Any) :: t
  def decode!(struct, binary, options)

  @doc """
  Encodes a conforming struct into binary

  Parameters:
    - struct: struct conforming to the `Ank.Frame.Encoder` protocol
    - options: options to pass as context to the encoding function
  """
  @spec encode!(t, Any) :: binary
  def encode!(struct, options)

end

defimpl Ankh.Frame.Encoder, for: Any do
  def decode!(_, _, _), do: nil
  def encode!(_, _), do: <<>>
end
