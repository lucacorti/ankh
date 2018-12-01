defmodule Ankh.Connection.Receiver do
  @moduledoc false
  use GenServer

  require Logger

  alias Ankh.{Frame, Connection, Stream}
  alias Ankh.Frame.{Error, GoAway, Ping, Settings, WindowUpdate}

  @frame_header_size 9

  @type receiver :: GenServer.server()

  @type args :: [uri: URI.t(), connection: pid | nil]

  @spec start_link(args, GenServer.options()) :: GenServer.on_start()
  def start_link(args, options \\ []) do
    GenServer.start_link(
      __MODULE__,
      Keyword.merge(args, connection: self()),
      options
    )
  end

  def init(args) do
    connection = Keyword.get(args, :connection)
    {:ok, uri} = Keyword.fetch(args, :uri)
    {:ok, %{buffer: <<>>, uri: uri, connection: connection}}
  end

  def handle_info(
        {:ssl, socket, data},
        %{buffer: buffer, connection: connection} = state
      ) do
    :ssl.setopts(socket, active: :once)
    {state, frames} = parse_frames(buffer <> data, state)

    for frame <- frames do
      case frame do
        %{stream_id: 0} ->
          :ok = handle_connection_frame(frame, state)

        %{stream_id: id} ->
          Stream.recv({:via, Registry, {Stream.Registry, {connection, id}}}, frame)
      end
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
      |> Frame.Registry.frame_for_type(type)
      |> struct()
      |> Frame.decode!(frame_data, [])

    {new_state, frames} = parse_frames(rest_data, state)
    {new_state, [frame | frames]}
  end

  defp parse_frames(_, state), do: {%{state | buffer: <<>>}, []}

  defp handle_connection_frame(
         %Settings{stream_id: 0, flags: %{ack: false}, payload: payload} = frame,
         %{connection: connection}
       ) do
    Logger.debug("STREAM 0 RECEIVED SETTINGS")
    :ok =
      Connection.send(connection, %Settings{
        frame
        | flags: %Settings.Flags{ack: true},
          payload: nil,
          length: 0
      })

    Connection.send_settings(connection, payload)
  end

  defp handle_connection_frame(
         %Settings{stream_id: 0, flags: %{ack: true}},
         _state
       ) do
    Logger.debug("STREAM 0 RECEIVED SETTINGS ACK")
    :ok
  end

  defp handle_connection_frame(
         %Ping{stream_id: 0, length: 8, flags: %{ack: false} = flags} = frame,
         %{connection: connection}
       ) do
    Logger.debug("STREAM 0 RECEIVED PING")
    Connection.send(connection, %Ping{
      frame
      | flags: %{
          flags
          | ack: true
        }
    })
  end

  defp handle_connection_frame(
         %WindowUpdate{stream_id: 0, payload: %{window_size_increment: 0}},
         _state
       ) do
     Logger.debug("STREAM 0 RECEIVED WINDOW_UPDATE with window_size increment 0")
    {:error, :protocol_error}
  end

  defp handle_connection_frame(
         %WindowUpdate{stream_id: 0, payload: %{window_size_increment: increment}},
         %{connection: connection}
       ) do
    Connection.window_update(connection, increment)
  end

  defp handle_connection_frame(%GoAway{stream_id: 0, payload: %{error_code: code}}, _state) do
    Logger.debug("STREAM 0 RECEIVED GO_AWAY #{inspect code}: #{Error.format(code)}")
    {:error, code}
  end
end
