defmodule Ankh.HTTP2.Frame.Data do
  @moduledoc false

  defmodule Flags do
    @moduledoc false

    @type t :: %__MODULE__{end_stream: boolean, padded: boolean}
    defstruct end_stream: false, padded: false
  end

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{pad_length: integer, data: binary}
    defstruct pad_length: 0, data: <<>>
  end

  alias __MODULE__.{Flags, Payload}
  use Ankh.HTTP2.Frame, type: 0x0, flags: Flags, payload: Payload
end

defimpl Ankh.HTTP2.Frame.Splittable, for: Ankh.HTTP2.Frame.Data do
  def split(%{flags: %{end_stream: end_stream} = flags} = frame, frame_size) do
    [frame | frames] = do_split(frame, frame_size, [])
    Enum.reverse([%{frame | flags: %{flags | end_stream: end_stream}} | frames])
  end

  defp do_split(%{payload: %{data: data}} = frame, frame_size, frames)
       when is_binary(data) and byte_size(data) <= frame_size do
    [clone_frame(frame, data) | frames]
  end

  defp do_split(%{payload: %{data: data}} = frame, frame_size, frames)
       when is_binary(data) do
    chunk = binary_part(data, 0, frame_size)
    rest = binary_part(data, frame_size, byte_size(data) - frame_size)
    frames = [clone_frame(frame, chunk) | frames]

    frame
    |> clone_frame(rest)
    |> do_split(frame_size, frames)
  end

  defp do_split(%{payload: %{data: []}}, _frame_size, frames), do: frames

  defp do_split(%{payload: %{data: [chunk | rest]}} = frame, frame_size, frames) do
    frames =
      frame
      |> clone_frame(chunk)
      |> do_split(frame_size, frames)

    frame
    |> clone_frame(rest)
    |> do_split(frame_size, frames)
  end

  defp clone_frame(%{flags: flags, payload: payload} = frame, data) do
    %{frame | flags: %{flags | end_stream: false}, payload: %{payload | data: data}}
  end
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Data.Flags do
  def decode(flags, <<_::4, 0::1, _::2, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, padded: false}}
  end

  def decode(flags, <<_::4, 0::1, _::2, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, padded: false}}
  end

  def decode(flags, <<_::4, 1::1, _::2, 0::1>>, _) do
    {:ok, %{flags | end_stream: false, padded: true}}
  end

  def decode(flags, <<_::4, 1::1, _::2, 1::1>>, _) do
    {:ok, %{flags | end_stream: true, padded: true}}
  end

  def decode(_flags, _data, _options), do: {:error, :decode_error}

  def encode(%{end_stream: false, padded: false}, _) do
    {:ok, <<0::4, 0::1, 0::2, 0::1>>}
  end

  def encode(%{end_stream: true, padded: false}, _) do
    {:ok, <<0::4, 0::1, 0::2, 1::1>>}
  end

  def encode(%{end_stream: false, padded: true}, _) do
    {:ok, <<0::4, 1::1, 0::2, 0::1>>}
  end

  def encode(%{end_stream: true, padded: true}, _) do
    {:ok, <<0::4, 1::1, 0::2, 1::1>>}
  end

  def encode(_flags, _options), do: {:error, :encode_error}
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Data.Payload do
  def decode(payload, <<pad_length::8, padded_data::binary>>, flags: %{padded: true}) do
    data = binary_part(padded_data, 0, byte_size(padded_data) - pad_length)
    {:ok, %{payload | pad_length: pad_length, data: data}}
  end

  def decode(payload, <<data::binary>>, flags: %{padded: false}) do
    {:ok, %{payload | data: data}}
  end

  def decode(_payload, _data, _options), do: {:error, :decode_error}

  def encode(%{pad_length: pad_length, data: data}, flags: %{padded: true}) do
    {:ok, [<<pad_length::8, data>>, :binary.copy(<<0>>, pad_length)]}
  end

  def encode(%{data: data}, flags: %{padded: false}) do
    {:ok, data}
  end

  def encode(_payload, _options), do: {:error, :encode_error}
end
