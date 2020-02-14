defprotocol Ankh.HTTP2.Frame.Encodable do
  @moduledoc """
  Protocol for encoding/decoding data types to/from wire format
  """

  @fallback_to_any true

  @typedoc "Data type conforming to the `Ankh.HTTP2.Frame.Encodable` protocol"
  @type t :: any()

  @typedoc "Encode/Decode options"
  @type options :: Keyword.t()

  @doc """
  Decodes a binary into an `Ankh.HTTP2.Frame.Encodable` conforming data type

  Parameters:
    - data: data type conforming to the `Ankh.HTTP2.Frame.Encodable` protocol
    - binary: data to decode into the struct
    - options: options to pass as context to the decoding function
  """
  @spec decode(t, binary, options) :: {:ok, t} | {:error, any()}
  def decode(struct, binary, options \\ [])

  @doc """
  Encodes an `Ankh.HTTP2.Frame.Encodable` conforming data type into an IO list

  Parameters:
    - data: data type conforming to the `Ankh.HTTP2.Frame.Encodable` protocol
    - options: options to pass as context to the encoding function
  """
  @spec encode(t, options) :: {:ok, iodata} | {:error, any()}
  def encode(data, options \\ [])
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Any do
  def decode(_, _, _), do: {:ok, nil}
  def encode(_, _), do: {:ok, <<>>}
end
