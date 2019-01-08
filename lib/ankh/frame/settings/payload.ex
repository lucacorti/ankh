defmodule Ankh.Frame.Settings.Payload do
  @moduledoc false

  @type t :: %__MODULE__{
          header_table_size: integer,
          enable_push: boolean,
          max_concurrent_streams: integer,
          initial_window_size: integer,
          max_frame_size: integer,
          max_header_list_size: integer
        }
  defstruct header_table_size: 4_096,
            enable_push: true,
            max_concurrent_streams: 128,
            initial_window_size: 2_147_483_647,
            max_frame_size: 16_384,
            max_header_list_size: 128
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.Settings.Payload do
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
    case parse_settings_payload(data) do
      parsed when is_list(parsed) ->
        {:ok,
         parsed
         |> Enum.reduce(payload, fn
           {key, value}, acc ->
             struct(acc, [{key, value}])
         end)}

      {:error, _reason} = error ->
        error
    end
  end

  def decode(_payload, _data, _options), do: {:error, :frame_size_error}

  def encode(
        %{
          header_table_size: hts,
          enable_push: true,
          max_concurrent_streams: mcs,
          initial_window_size: iws,
          max_frame_size: mfs,
          max_header_list_size: mhls
        },
        _
      ) do
    {:ok,
     [
       <<@header_table_size::16>>,
       <<hts::32>>,
       <<@enable_push::16>>,
       <<1::32>>,
       <<@max_concurrent_streams::16>>,
       <<mcs::32>>,
       <<@initial_window_size::16>>,
       <<iws::32>>,
       <<@max_frame_size::16>>,
       <<mfs::32>>,
       <<@max_header_list_size::16>>,
       <<mhls::32>>
     ]}
  end

  def encode(
        %{
          header_table_size: hts,
          enable_push: false,
          max_concurrent_streams: mcs,
          initial_window_size: iws,
          max_frame_size: mfs,
          max_header_list_size: mhls
        },
        _
      ) do
    {:ok,
     [
       <<@header_table_size::16>>,
       <<hts::32>>,
       <<@enable_push::16>>,
       <<0::32>>,
       <<@max_concurrent_streams::16>>,
       <<mcs::32>>,
       <<@initial_window_size::16>>,
       <<iws::32>>,
       <<@max_frame_size::16>>,
       <<mfs::32>>,
       <<@max_header_list_size::16>>,
       <<mhls::32>>
     ]}
  end

  def encode(_payload, _options), do: {:error, :encode_error}

  defp parse_settings_payload(<<@header_table_size::16, value::32, rest::binary>>) do
    [{:header_table_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@enable_push::16, 1::32, rest::binary>>) do
    [{:enable_push, true} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@enable_push::16, 0::32, rest::binary>>) do
    [{:enable_push, false} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@enable_push::16, _value::32, _rest::binary>>) do
    {:error, :protocol_error}
  end

  defp parse_settings_payload(<<@max_concurrent_streams::16, value::32, rest::binary>>) do
    [{:max_concurrent_streams, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@initial_window_size::16, value::32, _rest::binary>>)
       when value > @window_size_limit,
       do: {:error, :flow_control_error}

  defp parse_settings_payload(<<@initial_window_size::16, value::32, rest::binary>>) do
    [{:initial_window_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@max_frame_size::16, value::32, _rest::binary>>)
       when value < @frame_size_initial or value > @frame_size_limit,
       do: {:error, :protocol_error}

  defp parse_settings_payload(<<@max_frame_size::16, value::32, rest::binary>>) do
    [{:max_frame_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@max_header_list_size::16, value::32, rest::binary>>) do
    [{:max_header_list_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<_key::16, _value::32, rest::binary>>),
    do: parse_settings_payload(rest)

  defp parse_settings_payload(<<>>),
    do: []
end
