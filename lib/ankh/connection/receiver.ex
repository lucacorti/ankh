defmodule Ankh.Connection.Receiver do
  @moduledoc false
  use GenServer

  alias Ankh.Frame
  alias Ankh.Frame.Registry

  @frame_header_size 9

  @type receiver :: GenServer.server()

  @type args :: [uri: URI.t(), controlling_process: pid | nil]

  @spec start_link(args, GenServer.options()) :: GenServer.on_start()
  def start_link(args, options \\ []) do
    controlling_process = Keyword.get(args, :controlling_process, self())

    GenServer.start_link(
      __MODULE__,
      Keyword.merge(args, controlling_process: controlling_process),
      options
    )
  end

  def init(args) do
    controlling_process = Keyword.get(args, :controlling_process)
    {:ok, uri} = Keyword.fetch(args, :uri)
    {:ok, %{buffer: <<>>, uri: uri, controlling_process: controlling_process}}
  end

  def handle_info(
        {:ssl, socket, data},
        %{buffer: buffer, controlling_process: controlling_process} = state
      ) do
    :ssl.setopts(socket, active: :once)
    {state, frames} = parse_frames(buffer <> data, state)
    for frame <- frames do
      Process.send(controlling_process, {:ankh, :frame, frame}, [])
    end

    {:noreply, state}
  end

  def handle_info({:ssl_closed, _socket}, state), do: {:stop, {:shutdown, :closed}, state}

  def handle_info({:ssl_error, _socket, reason}, state), do: {:stop, {:shutdown, reason}, state}

  defp parse_frames(<<payload_length::24, _::binary>> = data, state)
       when @frame_header_size + payload_length > byte_size(data) do
    {%{state | buffer: data}, []}
  end

  defp parse_frames(<<payload_length::24, type::8, _::binary>> = data, %{uri: uri} = state) do
    frame_size = @frame_header_size + payload_length
    frame_data = binary_part(data, 0, frame_size)
    rest_size = byte_size(data) - frame_size
    rest_data = binary_part(data, frame_size, rest_size)

    frame =
      uri
      |> Registry.frame_for_type(type)
      |> struct()
      |> Frame.decode!(frame_data, [])

    {new_state, frames} = parse_frames(rest_data, state)
    {new_state, [frame | frames]}
  end

  defp parse_frames(_, state), do: {%{state | buffer: <<>>}, []}
end
