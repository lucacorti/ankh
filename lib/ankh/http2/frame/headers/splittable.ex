defimpl Ankh.HTTP2.Frame.Splittable, for: Ankh.HTTP2.Frame.Headers do
  alias Ankh.HTTP2.Frame.Continuation

  def split(%{flags: flags, payload: %{hbf: hbf}} = frame, frame_size)
      when byte_size(hbf) <= frame_size do
    [%{frame | flags: %{flags | end_headers: true}}]
  end

  def split(%{payload: %{hbf: hbf} = payload} = frame, frame_size) do
    <<chunk::size(frame_size), rest::binary>> = hbf

    do_split(
      %Continuation{
        flags: %Continuation.Flags{end_headers: false},
        payload: %Continuation.Payload{hbf: rest}
      },
      frame_size,
      [%{frame | payload: %{payload | hbf: chunk}}]
    )
  end

  defp do_split(
    %{stream_id: id, payload: %{hbf: hbf} = payload} = frame,
    frame_size,
    frames
  ) when byte_size(hbf) > frame_size do
    <<chunk::size(frame_size), rest::binary>> = hbf

    frames = [
    %Continuation{
      stream_id: id,
      flags: %Continuation.Flags{end_headers: false},
      payload: %Continuation.Payload{payload | hbf: chunk}
    } | frames]

    do_split(%{frame | payload: %{payload | hbf: rest}}, frame_size, frames)
  end

  defp do_split(
         %{stream_id: id, payload: %{hbf: hbf}},
         _frame_size,
         frames
       ) do
    frame = %Continuation{
      stream_id: id,
      flags: %Continuation.Flags{end_headers: true},
      payload: %Continuation.Payload{hbf: hbf}
    }

    Enum.reverse([frame | frames])
  end
end
