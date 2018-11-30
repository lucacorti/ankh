defimpl Ankh.Frame.Splittable, for: Ankh.Frame.Data do
  alias Ankh.Frame.Data

  def split(%Data{} = frame, frame_size, end_stream),
    do: do_split(frame, frame_size, [], end_stream)

  defp do_split(
         %Data{flags: flags, payload: %{data: data}} = frame,
         frame_size,
         end_stream,
         frames
       )
       when byte_size(data) <= frame_size do
    frame = %{frame | flags: %{flags | end_stream: end_stream}}
    Enum.reverse([frame | frames])
  end

  defp do_split(%Data{payload: %{data: data} = payload} = frame, frame_size, end_stream, frames) do
    <<chunk::size(frame_size), rest::binary>> = data
    frames = [%{frame | payload: %{payload | data: chunk}} | frames]
    do_split(%Data{payload: %{data: rest}}, frame_size, end_stream, frames)
  end
end
