defmodule Ankh.Connection.Receiver do
  @moduledoc false
  use GenServer

  require Logger

  alias Ankh.{Connection, Error, Frame, Stream}
  alias Ankh.Frame.{GoAway, Ping, Settings, WindowUpdate}

  @type receiver :: GenServer.server()

  @spec start_link(Connection.connection(), pid, GenServer.options()) :: GenServer.on_start()
  def start_link(connection, controlling_process, options \\ []) do
    GenServer.start_link(
      __MODULE__,
      [
        connection: connection,
        controlling_process: controlling_process
      ],
      options
    )
  end

  def init(args) do
    connection = Keyword.get(args, :connection)
    controlling_process = Keyword.get(args, :controlling_process)
    {:ok, %{buffer: <<>>, connection: connection, controlling_process: controlling_process}}
  end

  def handle_info(
        {:ssl, socket, data},
        %{buffer: buffer, connection: connection, controlling_process: controlling_process} =
          state
      ) do
    :ssl.setopts(socket, active: :once)

    (buffer <> data)
    |> Frame.to_stream()
    |> Enum.reduce_while({:noreply, %{state | buffer: buffer <> data}}, fn
      {rest, nil}, {:noreply, state} ->
        {:halt, {:noreply, %{state | buffer: rest}}}

      {rest, {_length, type, 0, data}}, {:noreply, state} ->
        with type when not is_nil(type) <- Frame.Registry.frame_for_type(connection, type),
             {:ok, frame} <- Frame.decode(struct(type), data),
             :ok <- recv_connection_frame(frame, connection) do
          {:cont, {:noreply, %{state | buffer: rest}}}
        else
          nil ->
            {:cont, {:noreply, %{state | buffer: rest}}}

          {:error, reason} = error ->
            Process.send(controlling_process, {:ankh, :error, 0, error}, [])
            Connection.error(connection, reason)
            {:halt, {:stop, error, %{state | buffer: rest}}}
        end

      {rest, {_length, type, id, data}}, {:noreply, state} ->
        with {:ok, ^id, stream} <- Connection.start_stream(connection, id, controlling_process),
             {:ok, _stream_state} <- Stream.recv(stream, type, data) do
          {:cont, {:noreply, %{state | buffer: rest}}}
        else
          {:error, reason} = error ->
            Connection.error(connection, reason)
            {:halt, {:stop, error, %{state | buffer: rest}}}
        end
    end)
  end

  def handle_info({:ssl_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:ssl_error, _socket, reason}, state) do
    error = {:error, :ssl.format_error(reason)}
    {:stop, error, state}
  end

  defp recv_connection_frame(
         %Settings{flags: %{ack: false}, payload: payload} = frame,
         connection
       ) do
    Logger.debug(fn -> "STREAM 0 RECEIVED SETTINGS #{inspect(payload)}" end)

    settings = %Settings{
      frame
      | flags: %Settings.Flags{ack: true},
        payload: nil,
        length: 0
    }

    with {:ok, data} <- Frame.encode(settings),
         :ok <- Connection.send(connection, data),
         :ok <- Connection.send_settings(connection, payload),
         do: :ok
  end

  defp recv_connection_frame(
         %Settings{length: 0, flags: %{ack: true}},
         _connection
       ) do
    Logger.debug("STREAM 0 RECEIVED SETTINGS ACK")
    :ok
  end

  defp recv_connection_frame(
         %Settings{flags: %{ack: true}},
         _connection
       ) do
    Logger.debug("STREAM 0 ERROR RECEIVED SETTINGS ACK WITH PAYLOAD")
    {:error, :frame_size_error}
  end

  defp recv_connection_frame(
         %Ping{length: 8, flags: %{ack: true}},
         _connection
       ) do
    Logger.debug("STREAM 0 RECEIVED PING ACK")
    :ok
  end

  defp recv_connection_frame(
         %Ping{length: 8, flags: %{ack: false} = flags} = frame,
         connection
       ) do
    Logger.debug("STREAM 0 RECEIVED PING")

    ping = %Ping{
      frame
      | flags: %{
          flags
          | ack: true
        }
    }

    with {:ok, data} <- Frame.encode(ping),
         :ok <- Connection.send(connection, data),
         do: :ok
  end

  defp recv_connection_frame(
         %Ping{length: length},
         _connection
       )
       when length != 8 do
    {:error, :frame_size_error}
  end

  defp recv_connection_frame(
         %WindowUpdate{payload: %{window_size_increment: 0}},
         _connection
       ) do
    Logger.debug("STREAM 0 RECEIVED WINDOW_UPDATE with window_size increment 0")
    {:error, :protocol_error}
  end

  defp recv_connection_frame(
         %WindowUpdate{payload: %{window_size_increment: increment}},
         connection
       ) do
    with :ok <- Connection.window_update(connection, increment),
         do: :ok
  end

  defp recv_connection_frame(%GoAway{payload: %{error_code: code}}, _connection) do
    Logger.debug(fn ->
      "STREAM 0 RECEIVED GO_AWAY #{inspect(code)}: #{Error.format(code)}"
    end)

    :ok
  end

  defp recv_connection_frame(frame, _connection) do
    Logger.debug(fn ->
      "STREAM 0 RECEIVED ILLEGAL FRAME #{inspect(frame)}"
    end)

    {:error, :protocol_error}
  end
end
