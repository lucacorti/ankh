defimpl Ankh.Frame.Splittable, for: Ankh.Frame.Headers do
  alias Ankh.Frame.Continuation

  def split(%{flags: %{end_stream: end_stream} = flags, payload: %{hbf: hbf}} = frame, frame_size)
      when byte_size(hbf) <= frame_size do
    [%{frame | flags: %{flags | end_headers: true, end_stream: end_stream}}]
  end

  def split(frame, frame_size) do
    do_split(frame, frame_size, [])
  end

  defp do_split(
         %{flags: %{end_stream: end_stream} = flags, payload: %{hbf: hbf} = payload} = frame,
         frame_size,
         []
       ) do
    <<chunk::size(frame_size), rest::binary>> = hbf
    frames = [%{frame | payload: %{payload | hbf: chunk}}]

    do_split(
      %{
        frame
        | flags: %{flags | end_stream: end_stream, end_headers: false},
          payload: %{hbf: rest}
      },
      frame_size,
      frames
    )
  end

  defp do_split(
         %{stream_id: id, payload: %{hbf: hbf}},
         frame_size,
         frames
       )
       when byte_size(hbf) <= frame_size do
    frame = %Continuation{
      stream_id: id,
      flags: %Continuation.Flags{end_headers: true},
      payload: %Continuation.Payload{hbf: hbf}
    }

    Enum.reverse([frame | frames])
  end

  defp do_split(
         %{stream_id: id, payload: %{hbf: hbf} = payload} = frame,
         frame_size,
         frames
       ) do
    <<chunk::size(frame_size), rest::binary>> = hbf

    frames = [
      %Continuation{
        stream_id: id,
        payload: %Continuation.Payload{payload | hbf: chunk}
      }
      | frames
    ]

    do_split(%{frame | payload: %{hbf: rest}}, frame_size, frames)
  end
end
