defmodule Ankh.HTTP2.Frame.Settings do
  @moduledoc false

  defmodule Flags do
    @moduledoc false

    @type t :: %__MODULE__{ack: boolean}
    defstruct ack: false

    defimpl Ankh.HTTP2.Frame.Encodable do
      def decode(flags, <<_::7, 1::1>>, _), do: {:ok, %{flags | ack: true}}
      def decode(flags, <<_::7, 0::1>>, _), do: {:ok, %{flags | ack: false}}
      def decode(_flags, _data, _options), do: {:error, :decode_error}

      def encode(%{ack: true}, _), do: {:ok, <<0::7, 1::1>>}
      def encode(%{ack: false}, _), do: {:ok, <<0::7, 0::1>>}
      def encode(_flags, _options), do: {:error, :encode_error}
    end
  end

  defmodule Payload do
    @moduledoc false

    @typedoc "Settings key"
    @type key ::
            :header_table_size
            | :enable_push
            | :max_concurrent_streams
            | :initial_window_size
            | :max_frame_size
            | :max_header_list_size

    @typedoc "Settings value"
    @type value :: integer | boolean

    @type t :: %__MODULE__{settings: list({key, value})}

    defstruct settings: []

    defimpl Ankh.HTTP2.Frame.Encodable do
      @header_table_size 0x1
      @enable_push 0x2
      @max_concurrent_streams 0x3
      @initial_window_size 0x4
      @max_frame_size 0x5
      @max_header_list_size 0x6

      @window_size_limit 2_147_483_647
      @frame_size_limit 16_777_215
      @frame_size_initial 16_384

      def decode(payload, data, _) when rem(byte_size(data), 6) == 0 do
        case decode_settings(data, []) do
          settings when is_list(settings) ->
            {:ok, %{payload | settings: Enum.reverse(settings)}}

          {:error, _reason} = error ->
            error
        end
      end

      def decode(_payload, _data, _options), do: {:error, :frame_size_error}

      defp decode_settings(<<@header_table_size::16, value::32, rest::binary>>, settings),
        do: decode_settings(rest, Keyword.merge(settings, [{:header_table_size, value}]))

      defp decode_settings(<<@enable_push::16, 1::32, rest::binary>>, settings),
        do: decode_settings(rest, Keyword.merge(settings, [{:enable_push, true}]))

      defp decode_settings(<<@enable_push::16, 0::32, rest::binary>>, settings),
        do: decode_settings(rest, Keyword.merge(settings, [{:enable_push, false}]))

      defp decode_settings(<<@enable_push::16, _value::32, _rest::binary>>, _settings),
        do: {:error, :protocol_error}

      defp decode_settings(<<@max_concurrent_streams::16, value::32, rest::binary>>, settings),
        do: decode_settings(rest, Keyword.merge(settings, [{:max_concurrent_streams, value}]))

      defp decode_settings(<<@initial_window_size::16, value::32, _rest::binary>>, _settings)
           when value > @window_size_limit,
           do: {:error, :flow_control_error}

      defp decode_settings(<<@initial_window_size::16, value::32, rest::binary>>, settings),
        do: decode_settings(rest, Keyword.merge(settings, [{:initial_window_size, value}]))

      defp decode_settings(<<@max_frame_size::16, value::32, _rest::binary>>, _settings)
           when value < @frame_size_initial or value > @frame_size_limit,
           do: {:error, :protocol_error}

      defp decode_settings(<<@max_frame_size::16, value::32, rest::binary>>, settings),
        do: decode_settings(rest, Keyword.merge(settings, [{:max_frame_size, value}]))

      defp decode_settings(<<@max_header_list_size::16, value::32, rest::binary>>, settings),
        do: decode_settings(rest, Keyword.merge(settings, [{:max_header_list_size, value}]))

      defp decode_settings(<<_key::16, _value::32, rest::binary>>, settings),
        do: decode_settings(rest, settings)

      defp decode_settings(<<>>, settings), do: settings

      def encode(%{settings: settings}, _options) do
        case encode_settings(settings, []) do
          settings when is_list(settings) ->
            {:ok, Enum.reverse(settings)}

          {:error, _reason} = error ->
            error
        end
      end

      def encode(_payload, _options), do: {:error, :encode_error}

      defp encode_settings([{:header_table_size, value} | rest], data),
        do: encode_settings(rest, [<<@header_table_size::16, value::32>> | data])

      defp encode_settings([{:enable_push, true} | rest], data),
        do: encode_settings(rest, [<<@enable_push::16, 1::32>> | data])

      defp encode_settings([{:enable_push, false} | rest], data),
        do: encode_settings(rest, [<<@enable_push::16, 0::32>> | data])

      defp encode_settings([{:enable_push, _value}, _rest], _data),
        do: {:error, :encode_error}

      defp encode_settings([{:max_concurrent_streams, value} | rest], data),
        do: encode_settings(rest, [<<@max_concurrent_streams::16, value::32>> | data])

      defp encode_settings([{:initial_window_size, value} | _rest], _data)
           when value < 0 or value > @window_size_limit,
           do: {:error, :flow_control_error}

      defp encode_settings([{:initial_window_size, value} | rest], data),
        do: encode_settings(rest, [<<@initial_window_size::16, value::32>> | data])

      defp encode_settings([{:max_frame_size, value} | _rest], _data)
           when value < @frame_size_initial or value > @frame_size_limit,
           do: {:error, :protocol_error}

      defp encode_settings([{:max_frame_size, value} | rest], data),
        do: encode_settings(rest, [<<@max_frame_size::16, value::32>> | data])

      defp encode_settings([{:max_header_list_size, value} | rest], data),
        do: encode_settings(rest, [<<@max_header_list_size::16, value::32>> | data])

      defp encode_settings([{_key, _value} | rest], data),
        do: encode_settings(rest, data)

      defp encode_settings([], data), do: data
    end
  end

  use Ankh.HTTP2.Frame, type: 0x4, flags: Flags, payload: Payload
end
