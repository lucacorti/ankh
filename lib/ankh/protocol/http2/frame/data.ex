defmodule Ankh.Protocol.HTTP2.Frame.Data do
  @moduledoc false

  defmodule Flags do
    @moduledoc false

    @type t :: %__MODULE__{end_stream: boolean(), padded: boolean()}
    defstruct end_stream: false, padded: false

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      def decode(%@for{} = flags, <<_::4, 0::1, _::2, 0::1>>, _options),
        do: {:ok, %{flags | end_stream: false, padded: false}}

      def decode(%@for{} = flags, <<_::4, 0::1, _::2, 1::1>>, _options),
        do: {:ok, %{flags | end_stream: true, padded: false}}

      def decode(%@for{} = flags, <<_::4, 1::1, _::2, 0::1>>, _options),
        do: {:ok, %{flags | end_stream: false, padded: true}}

      def decode(%@for{} = flags, <<_::4, 1::1, _::2, 1::1>>, _options),
        do: {:ok, %{flags | end_stream: true, padded: true}}

      def decode(_flags, _data, _options), do: {:error, :decode_error}

      def encode(%@for{end_stream: false, padded: false}, _options),
        do: {:ok, <<0::4, 0::1, 0::2, 0::1>>}

      def encode(%@for{end_stream: true, padded: false}, _options),
        do: {:ok, <<0::4, 0::1, 0::2, 1::1>>}

      def encode(%@for{end_stream: false, padded: true}, _options),
        do: {:ok, <<0::4, 1::1, 0::2, 0::1>>}

      def encode(%@for{end_stream: true, padded: true}, _options),
        do: {:ok, <<0::4, 1::1, 0::2, 1::1>>}

      def encode(_flags, _options), do: {:error, :encode_error}
    end
  end

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{pad_length: integer, data: binary}
    defstruct pad_length: 0, data: <<>>

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      alias Ankh.Protocol.HTTP2.Frame.Data.Flags

      def decode(%@for{} = payload, <<pad_length::8, padded_data::binary>>,
            flags: %Flags{padded: true}
          ) do
        {:ok,
         %{
           payload
           | pad_length: pad_length,
             data: binary_part(padded_data, 0, byte_size(padded_data) - pad_length)
         }}
      end

      def decode(%@for{} = payload, <<data::binary>>, flags: %Flags{padded: false}),
        do: {:ok, %{payload | data: data}}

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(%@for{pad_length: pad_length, data: data}, flags: %Flags{padded: true}),
        do: {:ok, [<<pad_length::8, data>>, :binary.copy(<<0>>, pad_length)]}

      def encode(%@for{data: data}, flags: %Flags{padded: false}), do: {:ok, data}

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP2.Frame, type: 0x0, flags: Flags, payload: Payload

  defimpl Ankh.Protocol.HTTP2.Frame.Splittable do
    alias Ankh.Protocol.HTTP2.Frame.Data.{Flags, Payload}

    def split(%@for{flags: %Flags{} = flags} = frame, frame_size) do
      [last_frame | frames] = do_split(frame, frame_size, [])

      Enum.reverse([
        %{last_frame | flags: %Flags{flags | end_stream: flags.end_stream}} | frames
      ])
    end

    defp do_split(%@for{payload: %Payload{data: data}} = frame, frame_size, frames)
         when is_binary(data) and byte_size(data) <= frame_size do
      [clone_frame(frame, data) | frames]
    end

    defp do_split(%@for{payload: %Payload{data: data}} = frame, frame_size, frames)
         when is_binary(data) do
      chunk = binary_part(data, 0, frame_size)
      rest = binary_part(data, frame_size, byte_size(data) - frame_size)
      frames = [clone_frame(frame, chunk) | frames]

      frame
      |> clone_frame(rest)
      |> do_split(frame_size, frames)
    end

    defp do_split(%@for{payload: %Payload{data: []}}, _frame_size, frames), do: frames

    defp do_split(%@for{payload: %Payload{data: [chunk | rest]}} = frame, frame_size, frames) do
      frames =
        frame
        |> clone_frame(chunk)
        |> do_split(frame_size, frames)

      frame
      |> clone_frame(rest)
      |> do_split(frame_size, frames)
    end

    defp clone_frame(
           %@for{flags: %Flags{} = flags, payload: %Payload{} = payload} = frame,
           data
         ) do
      %{
        frame
        | length: byte_size(data),
          flags: %{flags | end_stream: false},
          payload: %{payload | data: data}
      }
    end
  end
end
