defmodule Ankh.Connection.Receiver do
  use GenServer

  require Logger

  alias HPack.Table
  alias Ankh.{Connection, Frame, Stream}
  alias Frame.{Encoder, Registry, Continuation, Data, Goaway, Headers, Ping,
  PushPromise, Settings, WindowUpdate}

  @frame_header_size 9

  @type receiver :: GenServer.server

  @spec start_link([sender: Connection.connection, receiver: pid | nil,
  mode: :stream | :full], GenServer.options) :: GenServer.on_start
  def start_link(args, options \\ []) do
    GenServer.start_link(__MODULE__, args, options)
  end

  def init([sender: sender, receiver: receiver, mode: mode]) do
    with settings <- %Settings.Payload{},
        {:ok, recv_ctx} <- Table.start_link(settings.header_table_size) do
      {:ok, %{buffer: <<>>, sender: sender, receiver: receiver, mode: mode,
      recv_ctx: recv_ctx, recv_settings: settings, streams: %{},
      last_stream_id: 0, max_concurrent_streams: nil,
      window_size: 2_147_483_647}}
    end
  end

  @doc """
  Returns the existing stream for the id or returns it.
  """
  @spec stream(pid, Integer.t) :: {:ok, Stream.t}
  def stream(receiver, id), do: GenServer.call(receiver, {:stream, id})

  @doc """
  Returns the last stream id for the connection.
  """
  @spec last_stream_id(pid) :: {:ok, Integer.t}
  def last_stream_id(receiver), do: GenServer.call(receiver, {:last_stream_id})

  @doc """
  Updates the stream for the connection
  """
  @spec update_stream(pid, Integer.t, Stream) :: :ok
  def update_stream(receiver, id, stream) do
    GenServer.call(receiver, {:update_stream, id, stream})
  end

  def handle_call({:update_stream, id, stream}, _from, %{streams: streams} = state) do
    {:reply, :ok, %{state | streams: Map.put(streams, id, stream)}}
  end

  def handle_call({:stream, id}, _from, %{streams: streams} = state) do
    {stream, streams} = Map.get_and_update(streams, id, fn
      nil ->
        # mcs = Map.get(state, :max_concurrent_streams)
        # case concurrent_streams(streams) do
        #   n when is_integer(mcs) and is_integer(n) and n >= mcs ->
        #     :pop
        #   _ ->
            {nil, Stream.new(id)}
        # end
      existing_stream ->
        {existing_stream, existing_stream}
    end)

    # case Map.get(streams, id) do
    #   nil ->
    #     {:reply, {:error, :max_concurrent_streams}, %{state | streams: streams}}
    #   _stream ->
        {:reply, {:ok, Map.get(streams, id)}, %{state | streams: streams}}
    # end
  end

  def handle_call({:last_stream_id}, _from, %{last_stream_id: lsid} = state) do
    {:reply, {:ok, lsid}, state}
  end

  def handle_info({:ssl, socket, data}, %{buffer: buffer} = state) do
    :ssl.setopts(socket, active: :once)
    {state, frames} = buffer <> data
    |> parse_frames(state)

    {:noreply, Enum.reduce(frames, state, fn
      %{stream_id: id} = frame, %{streams: streams} = state ->
        receive_frame(state, Map.get(streams, id), frame)
    end)}
  end

  def handle_info({:ssl_closed, _socket}, state) do
    {:stop, {:shutdown, :closed}, state}
  end

  def handle_info({:ssl_error, _socket, reason}, state) do
    {:stop, {:shutdown, reason}, state}
  end

  defp concurrent_streams(streams) do
    Enum.count(streams, fn
      %Stream{state: :open} -> true
      %Stream{state: :half_closed_local} -> true
      %Stream{state: :half_closed_remote} -> true
      _ -> false
    end)
  end

  defp parse_frames(<<payload_length::24, _::binary>> = data, state)
  when @frame_header_size + payload_length > byte_size(data) do
    {%{state | buffer: data}, []}
  end

  defp parse_frames(<<payload_length::24, type::8, _::binary>> = data, state) do
    frame_size = @frame_header_size + payload_length
    frame_data = binary_part(data, 0, frame_size)
    rest_size = byte_size(data) - frame_size
    rest_data = binary_part(data, frame_size, rest_size)

    {old_state, frame} = type
    |> Registry.struct_for_type()
    |> Encoder.decode!(frame_data, [])
    |> decode_frame(state)

    {new_state, frames} = parse_frames(rest_data, old_state)
    {new_state, [frame | frames]}
  end

  defp parse_frames(_, state), do: {%{state | buffer: <<>>}, []}

  defp receive_frame(%{sender: sender} = state, _stream,
  %Ping{stream_id: 0, length: 8, flags: %{ack: false}} = frame) do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    :ok = Connection.send(sender, %Ping{frame |
      flags: %Ping.Flags{ack: true}
    })
    state
  end

  defp receive_frame(%{sender: sender, last_stream_id: lsid} = state, _stream,
  %Ping{stream_id: 0,flags: %{ack: false}} = frame) do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    :ok = Connection.send(sender, %Goaway{
      payload: %Goaway.Payload{
        last_stream_id: lsid, error_code: :frame_size_error
      }
    })
    state
  end

  defp receive_frame(%{sender: sender, last_stream_id: lsid} = state, _stream,
  %Ping{length: 8, flags: %{ack: false}} = frame) do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    :ok = Connection.send(sender, %Goaway{payload: %Goaway.Payload{
        last_stream_id: lsid, error_code: :protocol_error
      }
    })
    state
  end

  defp receive_frame(%{sender: sender} = state, _stream,
  %Settings{stream_id: 0, flags: %{ack: false}, payload: payload} = frame) do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    :ok = Connection.send(sender, %Settings{frame|
      flags: %Settings.Flags{ack: true}, payload: nil, length: 0
    })
    :ok = Connection.update_settings(sender, payload)
    %{state | max_concurrent_streams: payload.max_concurrent_streams}
  end

  defp receive_frame(state, _stream,
  %Settings{stream_id: 0, flags: %{ack: true}, length: 0} = frame) do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    state
  end

  defp receive_frame(%{sender: sender, last_stream_id: lsid} = state, _stream,
  %WindowUpdate{stream_id: id, payload: %{window_size_increment: increment}})
  when not is_integer(increment) or increment <= 0 do
    Logger.debug "STREAM #{id} ERROR window_size_increment #{increment}"
    :ok = Connection.send(sender, %Goaway{payload: %Goaway.Payload{
        last_stream_id: lsid, error_code: :protocol_error
      }
    })
    state
  end

  defp receive_frame(state, _stream, %WindowUpdate{stream_id: 0,
  payload: %{window_size_increment: increment}}) do
    Logger.debug "STREAM 0 window_size_increment #{increment}"
    %{state | window_size: state.window_size + increment}
  end

  defp receive_frame(%{streams: streams} = state, stream, %WindowUpdate{
  stream_id: id, payload: %{window_size_increment: increment}}) do
    Logger.debug "STREAM #{id} window_size_increment #{increment}"
    stream = %{stream | window_size: stream.window_size + increment}
    %{state | streams: Map.put(streams, id, stream)}
  end

  defp receive_frame(state, _stream, %Goaway{stream_id: 0,
  payload: %{error_code: code}} = frame) do
    Logger.debug "STREAM 0 RECEIVED FRAME #{inspect frame}"
    {:stop, code, state}
  end

  defp receive_frame(state, _stream, %{stream_id: 0} = frame) do
    Logger.error "STREAM 0 RECEIVED UNHANDLED FRAME #{inspect frame}"
    state
  end

  defp receive_frame(%{streams: streams} = state, stream,
  %{stream_id: id} = frame) do
    Logger.debug "STREAM #{id} RECEIVED #{inspect frame}"
    {:ok, stream} = Stream.received_frame(stream, frame)
    Logger.debug "STREAM #{id} IS #{inspect stream}"
    %{state | streams: Map.put(streams, id, stream), last_stream_id: id}
  end

  defp decode_frame(%{stream_id: 0} = frame, state), do: {state, frame}

  defp decode_frame(%Headers{stream_id: id, flags: %{end_headers: false},
  payload: %{header_block_fragment: hbf}} = frame, %{streams: streams} = state)
  do
    Logger.debug("STREAM #{id} RECEIVED PARTIAL HBF #{inspect hbf}")
    {_, streams} = Map.get_and_update(streams, id, fn
      a_stream ->
        {a_stream, %{a_stream | hbf: a_stream.hbf <> hbf}}
    end)
    {%{state | streams: streams}, frame}
  end

  defp decode_frame(%PushPromise{stream_id: id, flags: %{end_headers: false},
  payload: %{promised_stream_id: promised_id,
  header_block_fragment: hbf}} = frame, %{streams: streams} = state) do
    Logger.debug("STREAM #{id} RECEIVED PARTIAL HBF #{inspect hbf}")
    {_, streams} = Map.get_and_update(streams, id, fn
      a_stream ->
        {a_stream, %{a_stream | promised_id: promised_id,
         hbf_type: :push_promise, hbf: a_stream.hbf <> hbf}}
    end)
    {%{state | streams: streams}, frame}
  end

  defp decode_frame(%Continuation{stream_id: id, flags: %{end_headers: false},
  payload: %{header_block_fragment: hbf}} = frame, %{streams: streams} = state)
  do
    Logger.debug("STREAM #{id} RECEIVED PARTIAL HBF #{inspect hbf}")
    {_, streams} = Map.get_and_update(streams, id, fn
      a_stream ->
        {a_stream, %{a_stream | hbf: a_stream.hbf <> hbf}}
    end)
    {%{state | streams: streams}, frame}
  end

  defp decode_frame(%Headers{stream_id: id, flags: %{end_headers: true},
  payload: %{header_block_fragment: hbf}} = frame,
  %{streams: streams, recv_ctx: table, receiver: receiver} = state) do
    stream = Map.get(streams, id)
    headers = HPack.decode(stream.hbf <> hbf, table)
    Logger.debug("STREAM #{id} RECEIVED HEADERS #{inspect headers}")
    Process.send(receiver, {:ankh, :headers, id, headers}, [])
    {%{state | streams: Map.put(streams, id, %{stream | hbf: <<>>})}, frame}
  end

  defp decode_frame(%PushPromise{stream_id: id, flags: %{end_headers: true},
  payload: %{promised_stream_id: promised_id,
  header_block_fragment: hbf}} = frame,
  %{streams: streams, recv_ctx: table, receiver: receiver} = state) do
    stream = Map.get(streams, id)
    headers = HPack.decode(stream.hbf <> hbf, table)
    Logger.debug("STREAM #{id} RECEIVED HEADERS #{inspect headers}")
    Process.send(receiver, {:ankh, :push_promise, id, promised_id, headers}, [])
    streams = streams
    |> Map.put(id, %{stream | hbf: <<>>})
    |> Map.put(promised_id, Stream.new(promised_id, :reserved_remote))
    {%{state | streams: streams}, frame}
  end

  defp decode_frame(%Continuation{stream_id: id, flags: %{end_headers: true},
  payload: %{header_block_fragment: hbf}} = frame,
  %{streams: streams, recv_ctx: table, receiver: receiver} = state) do
    stream = Map.get(streams, id)
    headers = HPack.decode(stream.hbf <> hbf, table)
    Logger.debug("STREAM #{id} RECEIVED HEADERS #{inspect headers}")
    Process.send(receiver, {:ankh, stream.hbf_type, id, headers}, [])
    streams = case stream.hbf_type do
      :push_promise ->
        %{promised_id: promised_id} = stream
        streams
        |> Map.put(id, %{stream | hbf: <<>>})
        |> Map.put(promised_id, Stream.new(promised_id, :reserved_remote))
      _ ->
        Map.put(streams, id, %{stream | hbf: <<>>})
    end
    {%{state | streams: streams}, frame}
  end

  defp decode_frame(%Data{stream_id: id, flags: %{end_stream: false},
  payload: %{data: data}} = frame,
  %{streams: streams, receiver: receiver, mode: mode} = state) do
    {_, streams} = Map.get_and_update(streams, id, fn
      a_stream ->
        {a_stream, %{a_stream | data: a_stream.data <> data}}
    end)
    case mode do
      :stream ->
        Process.send(receiver, {:ankh, :stream_data, id, data}, [])
      _ ->
        Logger.debug("Full mode, not sending partial data")
    end
    {%{state | streams: streams}, frame}
  end

  defp decode_frame(%Data{stream_id: id, flags: %{end_stream: true},
  payload: %{data: data}} = frame,
  %{streams: streams, receiver: receiver, mode: mode} = state) do
    {a_stream, streams} = Map.get_and_update(streams, id, fn
      a_stream ->
        {a_stream, %{a_stream | data: a_stream.data <> data}}
    end)
    data = streams
    |> Map.get(id)
    |> Map.get(:data)
    Logger.debug("STREAM #{id} RECEIVED #{byte_size data} BYTES DATA:\n#{data}")
    case {mode, a_stream.data} do
      {:full, _} ->
        Process.send(receiver, {:ankh, :data, id, data}, [])
      {:stream, <<>>} ->
        Process.send(receiver, {:ankh, :stream_data, id, data}, [])
      _ ->
        Logger.debug("Streaming mode, not sending reassembled data")
    end
    {%{state | streams: Map.put(streams, id, %{a_stream | data: <<>>})}, frame}
  end

  defp decode_frame(frame, state), do: {state, frame}
end
