defprotocol Ankh.Frame.Encoder do
  @moduledoc """
  Protocol for encoding/decoding data between structs and binary
  """
  @fallback_to_any true

  @typedoc """
  Struct conforming to the `Ankh.Frame.Encoder` protocol
  """
  @type t :: struct

  @doc """
  Decodes a binary into a conforming struct

  Parameters:
    - struct: struct conforming to the `Ankh.Frame.Encoder` protocol
    - binary: data to decode into the struct
    - options: options to pass as context to the decoding function
  """
  @spec decode!(t, binary, Keyword.t) :: t
  def decode!(struct, binary, options)

  @doc """
  Encodes a conforming struct into binary

  Parameters:
    - struct: struct conforming to the `Ankh.Frame.Encoder` protocol
    - options: options to pass as context to the encoding function
  """
  @spec encode!(t, Keyword.t) :: binary
  def encode!(struct, options)
end

defimpl Ankh.Frame.Encoder, for: Any do
  def decode!(_, _, _), do: nil
  def encode!(_, _), do: <<>>
end
