defmodule Ankh.Connection.Receiver do
  @moduledoc false
  use GenServer

  require Logger

  alias Ankh.{Connection, Frame, Stream}
  alias Ankh.Frame.{Error, GoAway, Ping, Settings, WindowUpdate}

  @type receiver :: GenServer.server()

  @spec start_link(Keyword.t(), GenServer.options()) :: GenServer.on_start()
  def start_link(args \\ [], options \\ []) do
    GenServer.start_link(
      __MODULE__,
      Keyword.merge(args, connection: self()),
      options
    )
  end

  def init(args) do
    connection = Keyword.get(args, :connection)
    {:ok, %{buffer: <<>>, connection: connection}}
  end

  def handle_info(
        {:ssl, socket, data},
        %{buffer: buffer, connection: connection} = state
      ) do
    :ssl.setopts(socket, active: :once)
    {buffer, frames} = Frame.peek_frames(buffer <> data)
    state = %{state | buffer: buffer}

    frames
    |> Enum.reduce_while({:noreply, state}, fn
      {_length, type, 0, data}, acc ->
        with frame <- Frame.Registry.frame_for_type(connection, type),
             frame <- Frame.decode!(struct(frame), data),
             :ok <- handle_connection_frame(frame, state) do
          {:cont, acc}
        else
          error ->
            {:halt, {:stop, error, state}}
        end

      {_length, type, id, data}, acc ->
        Stream.recv_raw({:via, Registry, {Stream.Registry, {connection, id}}}, type, data)
        {:cont, acc}
    end)
  end

  def handle_info({:ssl_closed, _socket}, state) do
    error = {:error, "SSL closed"}
    {:stop, error, error, state}
  end

  def handle_info({:ssl_error, _socket, reason}, state) do
    error = {:error, :ssl.format_error(reason)}
    {:stop, error, error, state}
  end

  defp handle_connection_frame(
         %Settings{stream_id: 0, flags: %{ack: false}, payload: payload} = frame,
         %{connection: connection}
       ) do
    Logger.debug("STREAM 0 RECEIVED SETTINGS")

    :ok =
      Connection.send(
        connection,
        Frame.encode!(%Settings{
          frame
          | flags: %Settings.Flags{ack: true},
            payload: nil,
            length: 0
        })
      )

    :ok = Connection.send_settings(connection, payload)
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

    Connection.send(
      connection,
      Frame.encode!(%Ping{
        frame
        | flags: %{
            flags
            | ack: true
          }
      })
    )

    Logger.debug("STREAM 0 ACK PING")
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
    Logger.debug(fn ->
      "STREAM 0 RECEIVED GO_AWAY #{inspect(code)}: #{Error.format(code)}"
    end)

    {:error, code}
  end
end
