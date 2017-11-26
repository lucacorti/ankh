defprotocol Ankh.Frame.Payload do
  @moduledoc """
  Protocol for enoding/decoding payload data types
  """

  @fallback_to_any true

  @typedoc "Data type conforming to the `Ankh.Frame.Payload` protocol"
  @type t :: term | nil

  @typedoc "Payload decode options"
  @type options :: Keyword.t

  @doc """
  Decodes a binary into a conforming data type

  Parameters:
    - data: data type conforming to the `Ankh.Frame.Payload` protocol
    - binary: binary to decode into the data type
    - options: options to pass as context to the decoding function
  """
  @spec decode!(t, binary, options) :: t
  def decode!(data, binary, options \\ [])

  @doc """
  Encodes a conforming data type into an IO list

  Parameters:
    - data: data type conforming to the `Ankh.Frame.Payload` protocol
    - options: options to pass as context to the encoding function
  """
  @spec encode!(t, options) :: iodata
  def encode!(data, options \\ [])
end

defimpl Ankh.Frame.Payload, for: Any do
  def decode!(_, _, _), do: nil
  def encode!(_, _), do: <<>>
end
