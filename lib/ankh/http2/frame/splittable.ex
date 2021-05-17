defprotocol Ankh.HTTP2.Frame.Splittable do
  @moduledoc """
  Protocol for splitting frames after encoding to wire format
  """

  alias Ankh.HTTP2.Frame

  @fallback_to_any true

  @typedoc "Data type conforming to the `Ankh.HTTP2.Frame.Splittable` protocol"
  @type t :: any()

  @doc """
  Returns N frames for `frame` with the specified `frame_size`.
  """
  @spec split(t(), non_neg_integer()) :: [Frame.t()]
  def split(frame, frame_size)
end

defimpl Ankh.HTTP2.Frame.Splittable, for: Any do
  def split(frame, _), do: [frame]
end
