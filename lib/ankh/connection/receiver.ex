defmodule Ankh.Connection.Receiver do
  @moduledoc false
  use GenServer

  require Logger

  alias Ankh.{Connection, Error, Frame, Stream}
  alias Ankh.Frame.{GoAway, Ping, Priority, Settings, WindowUpdate}
  import Stream, only: [is_local: 2]

  @type t :: GenServer.server()

  @spec start_link(
          Connection.connection(),
          pid,
          integer(),
          integer(),
          atom(),
          GenServer.options()
        ) ::
          GenServer.on_start()
  def start_link(
        connection,
        controlling_process,
        first_local_stream_id,
        first_remote_stream_id,
        transport,
        options \\ []
      ) do
    GenServer.start_link(
      __MODULE__,
      [
        connection: connection,
        controlling_process: controlling_process,
        last_local_stream_id: first_local_stream_id,
        last_remote_stream_id: first_remote_stream_id,
        transport: transport
      ],
      options
    )
  end

  def init(args) do
    {:ok, Enum.into(args, %{buffer: <<>>, recv_hbf_type: nil})}
  end

  def handle_info(
        msg,
        %{
          buffer: buffer,
          connection: connection,
          controlling_process: controlling_process,
          transport: transport
        } = state
      ) do
    case transport.handle_msg(msg) do
      {:data, data} ->
        (buffer <> data)
        |> Frame.to_stream()
        |> Enum.reduce_while({:noreply, %{state | buffer: buffer <> data}}, fn
          {rest, nil}, {:noreply, state} ->
            {:halt, {:noreply, %{state | buffer: rest}}}

          {rest, {_length, type, 0, data}}, {:noreply, %{recv_hbf_type: recv_hbf_type} = state} ->
            with type when not is_nil(type) <- Frame.Registry.frame_for_type(connection, type),
                 {:ok, frame} <- Frame.decode(struct(type), data),
                 :ok <- recv_connection_frame(frame, connection) do
              {:cont, {:noreply, %{state | buffer: rest}}}
            else
              nil when is_nil(recv_hbf_type) ->
                {:cont, {:noreply, %{state | buffer: rest}}}

              nil ->
                {:halt, {:stop, {:error, :protocol_error}, %{state | buffer: rest}}}

              {:error, reason} ->
                Connection.error(connection, reason)
                {:halt, {:stop, reason, %{state | buffer: rest}}}
            end

          {rest, {_length, type, id, data}},
          {:noreply, %{last_local_stream_id: last_local_stream_id} = state}
          when is_local(last_local_stream_id, id) ->
            with stream when not is_nil(stream) <- Connection.get_stream(connection, id),
                 {:ok, _stream_state, recv_hbf_type} <- Stream.recv(stream, type, data) do
              last_local_stream_id = max(last_local_stream_id, id)

              {:cont,
               {:noreply,
                %{
                  state
                  | buffer: rest,
                    last_local_stream_id: last_local_stream_id,
                    recv_hbf_type: recv_hbf_type
                }}}
            else
              nil ->
                Connection.error(connection, :protocol_error)
                {:halt, {:noreply, %{state | buffer: rest}}}

              {:error, reason} ->
                Connection.error(connection, reason)
                {:halt, {:noreply, %{state | buffer: rest}}}
            end

          {rest, {_length, type, id, data}},
          {:noreply, %{last_remote_stream_id: last_remote_stream_id} = state} ->
            with %Priority{type: priority} <- %Priority{},
                 {:ok, _id, stream} when type == priority or id >= last_remote_stream_id <-
                   Connection.start_stream(connection, id, controlling_process),
                 {:ok, _stream_state, recv_hbf_type} <- Stream.recv(stream, type, data) do
              last_remote_stream_id = if type == priority, do: last_remote_stream_id, else: id

              {:cont,
               {:noreply,
                %{
                  state
                  | buffer: rest,
                    last_remote_stream_id: last_remote_stream_id,
                    recv_hbf_type: recv_hbf_type
                }}}
            else
              {:ok, _id, _stream} ->
                Connection.error(connection, :protocol_error)
                {:halt, {:noreply, %{state | buffer: rest}}}

              {:error, reason} ->
                Connection.error(connection, reason)
                {:halt, {:noreply, %{state | buffer: rest}}}
            end
        end)

      :closed ->
        {:stop, :normal, state}

      {:error, _msg} = error ->
        {:stop, error, state}
    end
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

    with :ok <- Connection.send_settings(connection, payload),
         {:ok, length, type, data} <- Frame.encode(settings),
         :ok <- Connection.send(connection, length, type, data),
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

    with {:ok, length, type, data} <- Frame.encode(ping),
         :ok <- Connection.send(connection, length, type, data),
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
         %WindowUpdate{length: length},
         _connection
       )
       when length != 4 do
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
