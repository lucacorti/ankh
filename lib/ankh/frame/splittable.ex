defprotocol Ankh.Frame.Splittable do
  @moduledoc """
  Protocol for splitting frames after encoding to wire format
  """

  alias Ankh.Frame

  @fallback_to_any true

  @typedoc "Data type conforming to the `Ankh.Frame.Splittable` protocol"
  @type t :: term | nil

  @typedoc "Encode/Decode options"
  @type options :: Keyword.t()

  @doc """
  Returns N frames for `frame` with the specified `frame_size`.
  """
  @spec split(frame :: t(), frame_size :: integer) :: [Frame.t()]
  def split(frame, frame_size)
end

defimpl Ankh.Frame.Splittable, for: Any do
  def split(frame, _), do: [frame]
end
