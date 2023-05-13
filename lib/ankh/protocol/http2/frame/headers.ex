defmodule Ankh.Protocol.HTTP2.Frame.Headers do
  @moduledoc false

  defmodule Flags do
    @moduledoc false

    @type t :: %__MODULE__{
            end_stream: boolean(),
            end_headers: boolean(),
            padded: boolean(),
            priority: boolean()
          }
    defstruct end_stream: false, end_headers: false, padded: false, priority: false

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      def decode(%@for{} = flags, <<_::2, 0::1, _::1, 0::1, 0::1, _::1, 0::1>>, _options) do
        {:ok, %{flags | end_stream: false, end_headers: false, padded: false, priority: false}}
      end

      def decode(%@for{} = flags, <<_::2, 0::1, _::1, 0::1, 0::1, _::1, 1::1>>, _options) do
        {:ok, %{flags | end_stream: true, end_headers: false, padded: false, priority: false}}
      end

      def decode(%@for{} = flags, <<_::2, 0::1, _::1, 0::1, 1::1, _::1, 1::1>>, _options) do
        {:ok, %{flags | end_stream: true, end_headers: true, padded: false, priority: false}}
      end

      def decode(%@for{} = flags, <<_::2, 0::1, _::1, 1::1, 1::1, _::1, 1::1>>, _options) do
        {:ok, %{flags | end_stream: true, end_headers: true, padded: true, priority: false}}
      end

      def decode(%@for{} = flags, <<_::2, 1::1, _::1, 1::1, 1::1, _::1, 1::1>>, _options) do
        {:ok, %{flags | end_stream: true, end_headers: true, padded: true, priority: true}}
      end

      def decode(%@for{} = flags, <<_::2, 1::1, _::1, 1::1, 1::1, _::1, 0::1>>, _options) do
        {:ok, %{flags | end_stream: false, end_headers: true, padded: true, priority: true}}
      end

      def decode(%@for{} = flags, <<_::2, 1::1, _::1, 1::1, 0::1, _::1, 0::1>>, _options) do
        {:ok, %{flags | end_stream: false, end_headers: false, padded: true, priority: true}}
      end

      def decode(%@for{} = flags, <<_::2, 1::1, _::1, 0::1, 0::1, _::1, 0::1>>, _options) do
        {:ok, %{flags | end_stream: false, end_headers: false, padded: false, priority: true}}
      end

      def decode(%@for{} = flags, <<_::2, 1::1, _::1, 0::1, 0::1, _::1, 1::1>>, _options) do
        {:ok, %{flags | end_stream: true, end_headers: false, padded: false, priority: true}}
      end

      def decode(%@for{} = flags, <<_::2, 1::1, _::1, 0::1, 1::1, _::1, 1::1>>, _options) do
        {:ok, %{flags | end_stream: true, end_headers: true, padded: false, priority: true}}
      end

      def decode(%@for{} = flags, <<_::2, 1::1, _::1, 1::1, 0::1, _::1, 1::1>>, _options) do
        {:ok, %{flags | end_stream: true, end_headers: false, padded: true, priority: true}}
      end

      def decode(%@for{} = flags, <<_::2, 0::1, _::1, 1::1, 0::1, _::1, 1::1>>, _options) do
        {:ok, %{flags | end_stream: true, end_headers: false, padded: true, priority: false}}
      end

      def decode(%@for{} = flags, <<_::2, 0::1, _::1, 1::1, 0::1, _::1, 0::1>>, _options) do
        {:ok, %{flags | end_stream: false, end_headers: false, padded: true, priority: false}}
      end

      def decode(%@for{} = flags, <<_::2, 0::1, _::1, 0::1, 1::1, _::1, 0::1>>, _options) do
        {:ok, %{flags | end_stream: false, end_headers: true, padded: false, priority: false}}
      end

      def decode(%@for{} = flags, <<_::2, 1::1, _::1, 0::1, 1::1, _::1, 0::1>>, _options) do
        {:ok, %{flags | end_stream: false, end_headers: true, padded: false, priority: true}}
      end

      def decode(%@for{} = flags, <<_::2, 0::1, _::1, 1::1, 1::1, _::1, 0::1>>, _options) do
        {:ok, %{flags | end_stream: false, end_headers: true, padded: true, priority: false}}
      end

      def decode(_flags, _data, _options), do: {:error, :decode_error}

      def encode(
            %@for{end_stream: false, end_headers: false, padded: false, priority: false},
            _options
          ),
          do: {:ok, <<0::2, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>}

      def encode(
            %@for{end_stream: true, end_headers: false, padded: false, priority: false},
            _options
          ),
          do: {:ok, <<0::2, 0::1, 0::1, 0::1, 0::1, 0::1, 1::1>>}

      def encode(
            %@for{end_stream: true, end_headers: true, padded: false, priority: false},
            _options
          ),
          do: {:ok, <<0::2, 0::1, 0::1, 0::1, 1::1, 0::1, 1::1>>}

      def encode(
            %@for{end_stream: true, end_headers: true, padded: true, priority: false},
            _options
          ),
          do: {:ok, <<0::2, 0::1, 0::1, 1::1, 1::1, 0::1, 1::1>>}

      def encode(
            %@for{end_stream: true, end_headers: true, padded: true, priority: true},
            _options
          ),
          do: {:ok, <<0::2, 1::1, 0::1, 1::1, 1::1, 0::1, 1::1>>}

      def encode(
            %@for{end_stream: false, end_headers: true, padded: true, priority: true},
            _options
          ),
          do: {:ok, <<0::2, 1::1, 0::1, 1::1, 1::1, 0::1, 0::1>>}

      def encode(
            %@for{end_stream: false, end_headers: false, padded: true, priority: true},
            _options
          ),
          do: {:ok, <<0::2, 1::1, 0::1, 1::1, 0::1, 0::1, 0::1>>}

      def encode(
            %@for{end_stream: false, end_headers: false, padded: false, priority: true},
            _options
          ),
          do: {:ok, <<0::2, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1>>}

      def encode(
            %@for{end_stream: true, end_headers: false, padded: false, priority: true},
            _options
          ),
          do: {:ok, <<0::2, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1>>}

      def encode(
            %@for{end_stream: true, end_headers: true, padded: false, priority: true},
            _options
          ),
          do: {:ok, <<0::2, 1::1, 0::1, 0::1, 1::1, 0::1, 1::1>>}

      def encode(
            %@for{end_stream: true, end_headers: false, padded: true, priority: true},
            _options
          ),
          do: {:ok, <<0::2, 1::1, 0::1, 1::1, 0::1, 0::1, 1::1>>}

      def encode(
            %@for{end_stream: true, end_headers: false, padded: true, priority: false},
            _options
          ),
          do: {:ok, <<0::2, 0::1, 0::1, 1::1, 0::1, 0::1, 1::1>>}

      def encode(
            %@for{end_stream: false, end_headers: false, padded: true, priority: false},
            _options
          ),
          do: {:ok, <<0::2, 0::1, 0::1, 1::1, 0::1, 0::1, 0::1>>}

      def encode(
            %@for{end_stream: false, end_headers: true, padded: false, priority: false},
            _options
          ),
          do: {:ok, <<0::2, 0::1, 0::1, 0::1, 1::1, 0::1, 0::1>>}

      def encode(
            %@for{end_stream: false, end_headers: true, padded: false, priority: true},
            _options
          ),
          do: {:ok, <<0::2, 1::1, 0::1, 0::1, 1::1, 0::1, 0::1>>}

      def encode(
            %@for{end_stream: false, end_headers: true, padded: true, priority: false},
            _options
          ),
          do: {:ok, <<0::2, 0::1, 0::1, 1::1, 1::1, 0::1, 0::1>>}

      def encode(_flags, _options), do: {:error, :encode_error}
    end
  end

  defmodule Payload do
    @moduledoc false
    alias Ankh.Protocol.HTTP2.Stream, as: HTTP2Stream

    @type t :: %__MODULE__{
            pad_length: non_neg_integer(),
            exclusive: boolean(),
            stream_dependency: HTTP2Stream.id(),
            weight: non_neg_integer(),
            hbf: binary()
          }
    defstruct pad_length: 0, exclusive: false, stream_dependency: 0, weight: 0, hbf: []

    defimpl Ankh.Protocol.HTTP2.Frame.Encodable do
      alias Ankh.Protocol.HTTP2.Frame.Headers.Flags

      def decode(
            %@for{} = payload,
            <<pl::8, 1::1, sd::31, wh::8, data::binary>>,
            flags: %Flags{padded: true, priority: true}
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
            %@for{} = payload,
            <<pl::8, 0::1, sd::31, wh::8, data::binary>>,
            flags: %Flags{padded: true, priority: true}
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

      def decode(
            %@for{} = payload,
            <<pl::8, data::binary>>,
            flags: %Flags{padded: true, priority: false}
          ) do
        {:ok, %{payload | pad_length: pl, hbf: binary_part(data, 0, byte_size(data) - pl)}}
      end

      def decode(
            %@for{} = payload,
            <<1::1, sd::31, wh::8, hbf::binary>>,
            flags: %Flags{padded: false, priority: true}
          ) do
        {:ok, %{payload | exclusive: true, weight: wh, stream_dependency: sd, hbf: hbf}}
      end

      def decode(
            %@for{} = payload,
            <<0::1, sd::31, wh::8, hbf::binary>>,
            flags: %Flags{padded: false, priority: true}
          ) do
        {:ok, %{payload | exclusive: false, weight: wh, stream_dependency: sd, hbf: hbf}}
      end

      def decode(
            %@for{} = payload,
            <<hbf::binary>>,
            flags: %Flags{padded: false, priority: false}
          ) do
        {:ok, %{payload | hbf: hbf}}
      end

      def decode(_payload, _data, _options), do: {:error, :decode_error}

      def encode(
            %@for{
              pad_length: pad_length,
              exclusive: true,
              stream_dependency: sd,
              weight: wh,
              hbf: hbf
            },
            flags: %Flags{padded: true, priority: true}
          ) do
        {:ok, [<<pad_length::8, 1::1, sd::31, wh::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
      end

      def encode(
            %@for{
              pad_length: pad_length,
              exclusive: false,
              stream_dependency: sd,
              weight: wh,
              hbf: hbf
            },
            flags: %Flags{padded: true, priority: true}
          ) do
        {:ok, [<<pad_length::8, 0::1, sd::31, wh::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
      end

      def encode(
            %@for{pad_length: pad_length, hbf: hbf},
            flags: %Flags{padded: true, priority: false}
          ) do
        {:ok, [<<pad_length::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
      end

      def encode(
            %@for{exclusive: true, stream_dependency: sd, weight: wh, hbf: hbf},
            flags: %Flags{padded: false, priority: true}
          ) do
        {:ok, [<<1::1, sd::31, wh::8>>, hbf]}
      end

      def encode(
            %@for{exclusive: false, stream_dependency: sd, weight: wh, hbf: hbf},
            flags: %Flags{padded: false, priority: true}
          ) do
        {:ok, [<<0::1, sd::31, wh::8>>, hbf]}
      end

      def encode(%@for{hbf: hbf}, flags: %Flags{padded: false, priority: false}),
        do: {:ok, [hbf]}

      def encode(_payload, _options), do: {:error, :encode_error}
    end
  end

  use Ankh.Protocol.HTTP2.Frame, type: 0x1, flags: Flags, payload: Payload

  defimpl Ankh.Protocol.HTTP2.Frame.Splittable do
    alias Ankh.Protocol.HTTP2.Frame.Continuation

    def split(%@for{flags: flags, payload: %@for.Payload{hbf: hbf}} = frame, frame_size)
        when byte_size(hbf) <= frame_size do
      [%@for{frame | flags: %@for.Flags{flags | end_headers: true}}]
    end

    def split(%@for{payload: %@for.Payload{hbf: hbf} = payload} = frame, frame_size) do
      <<chunk::size(frame_size), rest::binary>> = hbf

      do_split(
        %Continuation{
          flags: %Continuation.Flags{end_headers: false},
          payload: %Continuation.Payload{hbf: rest}
        },
        frame_size,
        [%@for{frame | payload: %@for.Payload{payload | hbf: chunk}}]
      )
    end

    defp do_split(
           %Continuation{stream_id: id, payload: %Continuation.Payload{hbf: hbf} = payload} =
             frame,
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

      do_split(
        %Continuation{frame | payload: %Continuation.Payload{payload | hbf: rest}},
        frame_size,
        frames
      )
    end

    defp do_split(
           %Continuation{stream_id: id, payload: %Continuation.Payload{hbf: hbf}},
           _frame_size,
           frames
         ) do
      Enum.reverse([
        %Continuation{
          stream_id: id,
          flags: %Continuation.Flags{end_headers: true},
          payload: %Continuation.Payload{hbf: hbf}
        }
        | frames
      ])
    end
  end
end
