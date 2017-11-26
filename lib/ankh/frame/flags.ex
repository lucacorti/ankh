defprotocol Ankh.Frame.Flags do
  @moduledoc """
  Protocol for enoding/decoding flags data types
  """

  @fallback_to_any true

  @typedoc "Data type conforming to the `Ankh.Frame.Flags` protocol"
  @type t :: term | nil

  @typedoc "Flags decode options"
  @type options :: Keyword.t

  @doc """
  Decodes a binary into a conforming data type

  Parameters:
    - data: data type conforming to the `Ankh.Frame.Flags` protocol
    - binary: data to decode into the struct
    - options: options to pass as context to the decoding function
  """
  @spec decode!(t, binary, options) :: t
  def decode!(struct, binary, options \\ [])

  @doc """
  Encodes a conforming struct into binary

  Parameters:
    - data: data conforming to the `Ankh.Frame.Flags` protocol
    - options: options to pass as context to the encoding function
  """
  @spec encode!(t, options) :: iodata
  def encode!(data, options \\ [])
end

defimpl Ankh.Frame.Flags, for: Any do
  def decode!(_, _, _), do: nil
  def encode!(_, _), do: <<>>
end
