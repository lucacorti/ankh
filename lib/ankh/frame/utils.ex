defmodule Ankh.Frame.Utils do
  @moduledoc """
  Utility functions for encoding/decoding values
  """

  alias Ankh.Frame
  alias Ankh.Frame.{Data, Continuation, Headers}

  @doc """
  Converts a boolean into the corresponding 0/1 integer values

  Raises on wrong arguments
  """
  @spec bool_to_int!(boolean) :: 0 | 1
  def bool_to_int!(false), do: 0
  def bool_to_int!(true), do: 1

  @doc """
  Converts 0/1 integers into the corresponding boolean values

  Raises on wrong arguments
  """
  @spec int_to_bool!(0 | 1) :: boolean
  def int_to_bool!(0), do: false
  def int_to_bool!(1), do: true

  @doc """
  Returns N frames for `frame` with the specified `frame_size`.

  DATA frames are split into multiple DATA frames.

  HEADERS frames are split into an initial HEADERS frame optionally followed by
  a number of CONTINUATION frames, the last frame has the END_HEADERS flag set.

  The `end_stream` parameter controls wether the END_STREAM flag is set on the
  last frame returned.
  """
  @spec split(frame :: Frame.t, frame_size :: Integer.t, end_stream :: boolean) :: [Frame.t]
  def split(frame, frame_size, end_stream \\ false)

  def split(%Data{} = frame, frame_size, end_stream), do: do_split(frame, frame_size, [], end_stream)

  def split(%Headers{flags: flags, payload: %{hbf: hbf}} = frame, frame_size, end_stream)
  when byte_size(hbf) <= frame_size do
    [%{frame | flags: %{flags | end_headers: true, end_stream: end_stream}}]
  end

  def split(%Headers{} = frame, frame_size, end_stream) do
    do_split(frame, frame_size, [], end_stream)
  end

  defp do_split(%Data{flags: flags, payload: %{data: data}} = frame, frame_size, end_stream, frames)
  when byte_size(data) <= frame_size do
    frame = %{frame | flags: %{flags | end_stream: end_stream}}
    Enum.reverse([frame | frames])
  end

  defp do_split(%Data{payload: %{data: data} = payload} = frame, frame_size, end_stream, frames) do
    <<chunk::size(frame_size), rest::binary>> = data
    frames = [%{frame | payload: %{payload | data: chunk}} | frames]
    do_split(%Data{payload: %{data: rest}}, frame_size, end_stream, frames)
  end

  defp do_split(%Headers{stream_id: id, flags: flags,  payload: %{hbf: hbf} = payload}, frame_size, end_stream, frames)
  when byte_size(hbf) <= frame_size do
    frame = %Continuation{stream_id: id, flags: %{flags | end_headers: true, end_stream: end_stream }, payload: %{payload | hbf: hbf}}
    Enum.reverse([frame | frames])
  end

  defp do_split(%Headers{flags: flags, payload: %{hbf: hbf} = payload} = frame, frame_size,  end_stream, []) do
    <<chunk::size(frame_size), rest::binary>> = hbf
    frames = [%{frame | payload: %{payload | hbf: chunk}}]
    do_split(%Headers{frame | flags: %{flags | end_headers: false}, payload: %{hbf: rest}}, frame_size, end_stream, frames)
  end

  defp do_split(%Headers{stream_id: id, payload: %{hbf: hbf} = payload}, frame_size, end_stream, frames) do
    <<chunk::size(frame_size), rest::binary>> = hbf
    frames = [%Continuation{stream_id: id, payload: %{payload | hbf: chunk}} | frames]
    do_split(%Headers{payload: %{hbf: rest}}, frame_size, end_stream, frames)
  end
end
