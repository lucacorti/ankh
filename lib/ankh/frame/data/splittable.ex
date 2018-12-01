defimpl Ankh.Frame.Splittable, for: Ankh.Frame.Data do
  def split(frame, frame_size),
    do: do_split(frame, frame_size, [])

  defp do_split(
         %{flags: %{end_stream: end_stream} = flags, payload: %{data: data}} = frame,
         frame_size,
         frames
       )
       when byte_size(data) <= frame_size do
    frame = %{frame | flags: %{flags | end_stream: end_stream}}
    Enum.reverse([frame | frames])
  end

  defp do_split(%{flags: flags, payload: %{data: data} = payload} = frame, frame_size, frames) do
    <<chunk::size(frame_size), rest::binary>> = data
    frames = [%{frame | flags: %{flags | end_stream: false}, payload: %{payload | data: chunk}} | frames]
    do_split(%{frame | payload: %{payload | data: rest}}, frame_size, frames)
  end
end
