defprotocol Ankh.Protocol.HTTP3.Frame.Encodable do
  @moduledoc """
  Protocol for encoding and decoding HTTP/3 frame payloads to and from their
  wire binary representation.

  Every concrete HTTP/3 frame payload module (e.g.
  `Ankh.Protocol.HTTP3.Frame.Data.Payload`) implements this protocol.

  Unlike the HTTP/2 equivalent (`Ankh.Protocol.HTTP2.Frame.Encodable`),
  HTTP/3 frames carry no per-frame flags byte, so encoding and decoding
  require no additional context beyond the payload struct itself and the raw
  binary.

  The `@fallback_to_any true` declaration provides a no-op implementation for
  `nil` payloads (frames whose payload field is not used).
  """

  @fallback_to_any true

  @typedoc "Any struct that implements `Ankh.Protocol.HTTP3.Frame.Encodable`."
  @type t :: any()

  @doc """
  Decode `binary` into the payload struct `data`.

  Returns `{:ok, updated_struct}` on success or `{:error, reason}` on failure.
  """
  @spec decode(t(), binary()) :: {:ok, t()} | {:error, any()}
  def decode(data, binary)

  @doc """
  Encode the payload struct into an `iodata()` wire representation.

  Returns `{:ok, iodata}` on success or `{:error, reason}` on failure.
  """
  @spec encode(t()) :: {:ok, iodata()} | {:error, any()}
  def encode(data)
end

defimpl Ankh.Protocol.HTTP3.Frame.Encodable, for: Any do
  # Fallback for nil payload fields (frames with no payload struct).
  def decode(_, _), do: {:ok, nil}
  def encode(_), do: {:ok, <<>>}
end
