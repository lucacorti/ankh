defprotocol Ankh.Frame.Encoder do
  @fallback_to_any true

  def decode!(struct, binary, options)
  def encode!(struct, options)
end

defimpl Ankh.Frame.Encoder, for: Any do
  def decode!(_, _, _), do: nil
  def encode!(_, _), do: <<>>
end
