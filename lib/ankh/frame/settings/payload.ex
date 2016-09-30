defmodule Ankh.Frame.Settings.Payload do
  @moduledoc """
  SETTINGS frame payload
  """

  @type t :: %__MODULE__{header_table_size: Integer.t, enable_push: boolean,
  max_concurrent_streams: Integer.t, initial_window_size: Intger.t,
  max_frame_size: Integer.t, max_header_list_size: Integer.t}
  defstruct [header_table_size: 4_096, enable_push: true,
             max_concurrent_streams: 128, initial_window_size: 65_535,
             max_frame_size: 16_384, max_header_list_size: 128]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Settings.Payload do
  import Ankh.Frame.Utils

  @header_table_size      0x1
  @enable_push            0x2
  @max_concurrent_streams 0x3
  @initial_window_size    0x4
  @max_frame_size         0x5
  @max_header_list_size   0x6

  def decode!(struct, binary, _) do
    binary
    |> parse_settings_payload
    |> Enum.reduce(struct, fn {key, value}, acc -> Map.put(acc, key, value) end)
  end

  def encode!(%{header_table_size: hts, enable_push: ep,
  max_concurrent_streams: mcs, initial_window_size: iws, max_frame_size: mfs,
  max_header_list_size: mhls}, _) do
    <<@header_table_size::16, hts::32,
      @enable_push::16, bool_to_int!(ep)::32,
      @max_concurrent_streams::16, mcs::32,
      @initial_window_size::16, iws::32,
      @max_frame_size::16, mfs::32,
      @max_header_list_size::16, mhls::32>>
  end

  defp parse_settings_payload(<<@header_table_size::16, value::32,
  rest::binary>>) do
    [{:header_table_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@enable_push::16, value::32,
  rest::binary>>) do
    [{:enable_push, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@max_concurrent_streams::16, value::32,
  rest::binary>>) do
    [{:max_concurrent_streams, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@initial_window_size::16, value::32,
  rest::binary>>) do
    [{:initial_window_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@max_frame_size::16, value::32,
  rest::binary>>) do
    [{:max_frame_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(<<@max_header_list_size::16, value::32,
  rest::binary>>) do
    [{:max_header_list_size, value} | parse_settings_payload(rest)]
  end

  defp parse_settings_payload(_), do: []
end
