defmodule Ankh.HTTP2.Frame.Headers do
  @moduledoc false

  defmodule Flags do
    @moduledoc false

    @type t :: %__MODULE__{
            end_stream: boolean,
            end_headers: boolean,
            padded: boolean,
            priority: boolean
          }
    defstruct end_stream: false, end_headers: false, padded: false, priority: false

    defimpl Ankh.HTTP2.Frame.Encodable do
      def decode(flags, <<_::2, 0::1, _::1, 0::1, 0::1, _::1, 0::1>>, _) do
        {:ok, %{flags | end_stream: false, end_headers: false, padded: false, priority: false}}
      end

      def decode(flags, <<_::2, 0::1, _::1, 0::1, 0::1, _::1, 1::1>>, _) do
        {:ok, %{flags | end_stream: true, end_headers: false, padded: false, priority: false}}
      end

      def decode(flags, <<_::2, 0::1, _::1, 0::1, 1::1, _::1, 1::1>>, _) do
        {:ok, %{flags | end_stream: true, end_headers: true, padded: false, priority: false}}
      end

      def decode(flags, <<_::2, 0::1, _::1, 1::1, 1::1, _::1, 1::1>>, _) do
        {:ok, %{flags | end_stream: true, end_headers: true, padded: true, priority: false}}
      end

      def decode(flags, <<_::2, 1::1, _::1, 1::1, 1::1, _::1, 1::1>>, _) do
        {:ok, %{flags | end_stream: true, end_headers: true, padded: true, priority: true}}
      end

      def decode(flags, <<_::2, 1::1, _::1, 1::1, 1::1, _::1, 0::1>>, _) do
        {:ok, %{flags | end_stream: false, end_headers: true, padded: true, priority: true}}
      end

      def decode(flags, <<_::2, 1::1, _::1, 1::1, 0::1, _::1, 0::1>>, _) do
        {:ok, %{flags | end_stream: false, end_headers: false, padded: true, priority: true}}
      end

      def decode(flags, <<_::2, 1::1, _::1, 0::1, 0::1, _::1, 0::1>>, _) do
        {:ok, %{flags | end_stream: false, end_headers: false, padded: false, priority: true}}
      end

      def decode(flags, <<_::2, 1::1, _::1, 0::1, 0::1, _::1, 1::1>>, _) do
        {:ok, %{flags | end_stream: true, end_headers: false, padded: false, priority: true}}
      end

      def decode(flags, <<_::2, 1::1, _::1, 0::1, 1::1, _::1, 1::1>>, _) do
        {:ok, %{flags | end_stream: true, end_headers: true, padded: false, priority: true}}
      end

      def decode(flags, <<_::2, 1::1, _::1, 1::1, 0::1, _::1, 1::1>>, _) do
        {:ok, %{flags | end_stream: true, end_headers: false, padded: true, priority: true}}
      end

      def decode(flags, <<_::2, 0::1, _::1, 1::1, 0::1, _::1, 1::1>>, _) do
        {:ok, %{flags | end_stream: true, end_headers: false, padded: true, priority: false}}
      end

      def decode(flags, <<_::2, 0::1, _::1, 1::1, 0::1, _::1, 0::1>>, _) do
        {:ok, %{flags | end_stream: false, end_headers: false, padded: true, priority: false}}
      end

      def decode(flags, <<_::2, 0::1, _::1, 0::1, 1::1, _::1, 0::1>>, _) do
        {:ok, %{flags | end_stream: false, end_headers: true, padded: false, priority: false}}
      end

      def decode(flags, <<_::2, 1::1, _::1, 0::1, 1::1, _::1, 0::1>>, _) do
        {:ok, %{flags | end_stream: false, end_headers: true, padded: false, priority: true}}
      end

      def decode(flags, <<_::2, 0::1, _::1, 1::1, 1::1, _::1, 0::1>>, _) do
        {:ok, %{flags | end_stream: false, end_headers: true, padded: true, priority: false}}
      end

      def decode(_flags, _data, _options), do: {:error, :decode_error}

      def encode(%{end_stream: false, end_headers: false, padded: false, priority: false}, _) do
        {:ok, <<0::2, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>}
      end

      def encode(%{end_stream: true, end_headers: false, padded: false, priority: false}, _) do
        {:ok, <<0::2, 0::1, 0::1, 0::1, 0::1, 0::1, 1::1>>}
      end

      def encode(%{end_stream: true, end_headers: true, padded: false, priority: false}, _) do
        {:ok, <<0::2, 0::1, 0::1, 0::1, 1::1, 0::1, 1::1>>}
      end

      def encode(%{end_stream: true, end_headers: true, padded: true, priority: false}, _) do
        {:ok, <<0::2, 0::1, 0::1, 1::1, 1::1, 0::1, 1::1>>}
      end

      def encode(%{end_stream: true, end_headers: true, padded: true, priority: true}, _) do
        {:ok, <<0::2, 1::1, 0::1, 1::1, 1::1, 0::1, 1::1>>}
      end

      def encode(%{end_stream: false, end_headers: true, padded: true, priority: true}, _) do
        {:ok, <<0::2, 1::1, 0::1, 1::1, 1::1, 0::1, 0::1>>}
      end

      def encode(%{end_stream: false, end_headers: false, padded: true, priority: true}, _) do
        {:ok, <<0::2, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1>>}
      end

      def encode(%{end_stream: false, end_headers: false, padded: false, priority: true}, _) do
        {:ok, <<0::2, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1>>}
      end

      def encode(%{end_stream: true, end_headers: false, padded: false, priority: true}, _) do
        {:ok, <<0::2, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1>>}
      end

      def encode(%{end_stream: true, end_headers: true, padded: false, priority: true}, _) do
        {:ok, <<0::2, 1::1, 0::1, 0::1, 1::1, 0::1, 1::1>>}
      end

      def encode(%{end_stream: true, end_headers: false, padded: true, priority: true}, _) do
        {:ok, <<0::2, 1::1, 0::1, 1::1, 0::1, 0::1, 1::1>>}
      end

      def encode(%{end_stream: true, end_headers: false, padded: true, priority: false}, _) do
        {:ok, <<0::2, 0::1, 0::1, 1::1, 0::1, 0::1, 1::1>>}
      end

      def encode(%{end_stream: false, end_headers: false, padded: true, priority: false}, _) do
        {:ok, <<0::2, 0::1, 0::1, 1::1, 0::1, 0::1, 0::1>>}
      end

      def encode(%{end_stream: false, end_headers: true, padded: false, priority: false}, _) do
        {:ok, <<0::2, 0::1, 0::1, 0::1, 1::1, 0::1, 0::1>>}
      end

      def encode(%{end_stream: false, end_headers: true, padded: false, priority: true}, _) do
        {:ok, <<0::2, 1::1, 0::1, 0::1, 1::1, 0::1, 0::1>>}
      end

      def encode(%{end_stream: false, end_headers: true, padded: true, priority: false}, _) do
        {:ok, <<0::2, 0::1, 0::1, 1::1, 1::1, 0::1, 0::1>>}
      end

      def encode(_flags, _options), do: {:error, :encode_error}
    end
  end

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{
            pad_length: integer,
            exclusive: boolean,
            stream_dependency: integer,
            weight: integer,
            hbf: binary
          }
    defstruct pad_length: 0, exclusive: false, stream_dependency: 0, weight: 0, hbf: []

    defimpl Ankh.HTTP2.Frame.Encodable do
      def decode(
            payload,
            <<pl::8, 1::1, sd::31, wh::8, data::binary>>,
            flags: %{padded: true, priority: true}
          ) do
        {:ok,
         %{
           payload
           | pad_length: pl,
             exclusive: true,
             weight: wh,
             stream_dependency: sd,
             hbf: binary_part(data, 0, byte_size(data) - pl)
         }}
      end

      def decode(
            payload,
            <<pl::8, 0::1, sd::31, wh::8, data::binary>>,
            flags: %{padded: true, priority: true}
          ) do
        {:ok,
         %{
           payload
           | pad_length: pl,
             exclusive: false,
             weight: wh,
             stream_dependency: sd,
             hbf: binary_part(data, 0, byte_size(data) - pl)
         }}
      end

      def decode(payload, <<pl::8, data::binary>>, flags: %{padded: true, priority: false}) do
        {:ok, %{payload | pad_length: pl, hbf: binary_part(data, 0, byte_size(data) - pl)}}
      end

      def decode(
            payload,
            <<1::1, sd::31, wh::8, hbf::binary>>,
            flags: %{padded: false, priority: true}
          ) do
        {:ok, %{payload | exclusive: true, weight: wh, stream_dependency: sd, hbf: hbf}}
      end

      def decode(
            payload,
            <<0::1, sd::31, wh::8, hbf::binary>>,
            flags: %{padded: false, priority: true}
          ) do
        {:ok, %{payload | exclusive: false, weight: wh, stream_dependency: sd, hbf: hbf}}
      end

      def decode(payload, <<hbf::binary>>, flags: %{padded: false, priority: false}) do
        {:ok, %{payload | hbf: hbf}}
      end

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(
            %{
              pad_length: pad_length,
              exclusive: true,
              stream_dependency: sd,
              weight: wh,
              hbf: hbf
            },
            flags: %{padded: true, priority: true}
          ) do
        {:ok, [<<pad_length::8, 1::1, sd::31, wh::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
      end

      def encode(
            %{
              pad_length: pad_length,
              exclusive: false,
              stream_dependency: sd,
              weight: wh,
              hbf: hbf
            },
            flags: %{padded: true, priority: true}
          ) do
        {:ok, [<<pad_length::8, 0::1, sd::31, wh::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
      end

      def encode(%{pad_length: pad_length, hbf: hbf}, flags: %{padded: true, priority: false}) do
        {:ok, [<<pad_length::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
      end

      def encode(
            %{exclusive: true, stream_dependency: sd, weight: wh, hbf: hbf},
            flags: %{padded: false, priority: true}
          ) do
        {:ok, [<<1::1, sd::31, wh::8>>, hbf]}
      end

      def encode(
            %{exclusive: false, stream_dependency: sd, weight: wh, hbf: hbf},
            flags: %{padded: false, priority: true}
          ) do
        {:ok, [<<0::1, sd::31, wh::8>>, hbf]}
      end

      def encode(%{hbf: hbf}, flags: %{padded: false, priority: false}) do
        {:ok, [hbf]}
      end

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.HTTP2.Frame, type: 0x1, flags: Flags, payload: Payload

  defimpl Ankh.HTTP2.Frame.Splittable do
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
         )
         when byte_size(hbf) > frame_size do
      <<chunk::size(frame_size), rest::binary>> = hbf

      frames = [
        %Continuation{
          stream_id: id,
          flags: %Continuation.Flags{end_headers: false},
          payload: %Continuation.Payload{payload | hbf: chunk}
        }
        | frames
      ]

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
end
