defimpl Ankh.HTTP2.Frame.Splittable, for: Ankh.HTTP2.Frame.Data do
  def split(frame, frame_size),
    do: do_split(frame, frame_size, [])

  defp do_split(%{payload: %{data: data}} = frame, frame_size, frames)
       when byte_size(data) <= frame_size do
    Enum.reverse([frame | frames])
  end

  defp do_split(%{flags: flags, payload: %{data: data} = payload} = frame, frame_size, frames) do
    chunk = binary_part(data, 0, frame_size)
    rest = binary_part(data, frame_size, byte_size(data) - frame_size)

    frames = [
      %{frame | flags: %{flags | end_stream: false}, payload: %{payload | data: chunk}} | frames
    ]

    do_split(%{frame | payload: %{payload | data: rest}}, frame_size, frames)
  end
end
