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

  def decode(payload, data, _) when is_binary(data) do
    payload =
      data
      |> parse_settings_payload
      |> Enum.reduce(payload, fn {key, value}, acc -> Map.put(acc, key, value) end)

    {:ok, payload}
  end

  def decode(_payload, _data, _options), do: {:error, :decode_error}

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

  defp parse_settings_payload(<<@enable_push::16, value::32, rest::binary>>) do
    [{:enable_push, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@max_concurrent_streams::16, value::32, rest::binary>>) do
    [{:max_concurrent_streams, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@initial_window_size::16, value::32, rest::binary>>) do
    [{:initial_window_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@max_frame_size::16, value::32, rest::binary>>) do
    [{:max_frame_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@max_header_list_size::16, value::32, rest::binary>>) do
    [{:max_header_list_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(_), do: []
end
