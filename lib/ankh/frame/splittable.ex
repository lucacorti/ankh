defprotocol Ankh.Frame.Splittable do
  @moduledoc """
  Protocol for splitting frames after encoding to wire format
  """

  @fallback_to_any true

  @typedoc "Data type conforming to the `Ankh.Frame.Splittable` protocol"
  @type t :: term | nil

  @typedoc "Encode/Decode options"
  @type options :: Keyword.t()

  @doc """
  Returns N frames for `frame` with the specified `frame_size`.
  """
  @spec split(frame :: t(), frame_size :: Integer.t(), end_stream :: boolean) :: [Frame.t()]
  def split(frame, frame_size, end_stream \\ false)
end

defimpl Ankh.Frame.Splittable, for: Any do
  def split(frame, _, _), do: [frame]
end
