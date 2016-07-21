defmodule Http2.Connection do
  use GenServer

  alias Http2.Frame
  alias Http2.Frame.{Encoder, Error}
  alias Http2.Frame.{Continuation, GoAway, Headers, Ping, PushPromise, Settings}

  require Logger

  @ssl_opts binary: true, versions: [:"tlsv1.2"],
            alpn_advertised_protocols: ["h2"]
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @frame_header_size 9
  @max_stream_id 2_147_483_648

  def start_link(%URI{} = uri, options \\ []) do
    GenServer.start_link(__MODULE__, uri, options)
  end

  def init(uri) do
    with {:ok, recv_ctx} = HPack.Table.start_link(4_096),
         {:ok, send_ctx} = HPack.Table.start_link(4_096) do
      {:ok, %{uri: uri, socket: nil, streams: %{}, last_stream_id: 0,
      buffer: <<>>, recv_hpack_ctx: recv_ctx, send_hpack_ctx: send_ctx}}
    end
  end

  def send(connection, %Frame{} = frame) do
    GenServer.call(connection, {:send, frame})
  end

  def close(pid), do: GenServer.call(pid, {:close})

  def handle_call({:send, frame}, from, %{socket: nil, uri: %URI{host: host,
  port: port}} = state) do
    hostname = String.to_charlist(host)
    ssl_options = @ssl_opts
    with {:ok, socket} <- :ssl.connect(hostname, port, ssl_options),
         :ok <- :ssl.send(socket, @preface) do
      handle_call({:send, frame}, from, %{state | socket: socket})
    else
      error ->
        {:stop, :ssl.format_error(error), state}
    end
  end

  def handle_call({:send, frame}, _from, state) do
    case send_frame(state, frame) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, error} ->
        {:stop, error, state}
    end
  end

  def handle_call({:close}, _from, %{socket: socket} = state) do
    :ok = :ssl.close(socket)
    {:stop, :closed, state}
  end

  def handle_info({:ssl, _socket, data}, %{buffer: buffer} = state) do
    {state, frames} = buffer <> data
    |> parse_frames(state)

    state = frames
    |> Enum.reduce(state, fn frame, state -> receive_frame(state, frame) end)
    {:noreply, state}
  end

  def handle_info({:ssl_closed, _socket}, state) do
    {:stop, :closed, state}
  end

  def handle_info(msg, state) do
    Logger.error "UNKNOWN MESSAGE: #{inspect msg}"
    {:noreply, state}
  end

  defp send_frame(%{socket: socket} = state, %Frame{stream_id: 0} = frame) do
    Logger.debug "STREAM 0 SEND #{inspect frame}"
    case :ssl.send(socket, Encoder.encode!(frame, [])) do
      :ok ->
        {:ok, state}
      error ->
        :ssl.format_error(error)
    end
  end

  defp send_frame(%{socket: socket, streams: streams, send_hpack_ctx: hpack}
  = state, %Frame{stream_id: id} = frame) do
    stream = Map.get(streams, id, Http2.Stream.new(id))
    Logger.debug "STREAM #{id} SEND #{inspect frame}"
    {:ok, stream} = Http2.Stream.send_frame(stream, frame)
    Logger.debug "STREAM #{id} IS #{inspect stream}"

    frame = case frame do
      %Frame{type: :headers, payload: %{header_block_fragment: headers}
      = payload} ->
        hbf = HPack.encode(headers, hpack)
        %{frame | payload: %{payload | header_block_fragment: hbf}}
      %Frame{type: :push_promise, payload: %{header_block_fragment: headers}
      = payload} ->
        hbf = HPack.encode(headers, hpack)
        %{frame | payload: %{payload | header_block_fragment: hbf}}
      _ ->
        frame
    end

    case :ssl.send(socket,  Encoder.encode!(frame, [])) do
      :ok ->
        {:ok, %{state | streams: Map.put(streams, id, stream)}}
      error ->
        :ssl.format_error(error)
    end
  end

  defp receive_frame(state, %Frame{stream_id: 0, length: 8, type: :ping,
  flags: %Ping.Flags{ack: false}, payload: %Ping.Payload{}} = frame) do
    Logger.debug "STREAM 0 RECV #{inspect frame}"
    {:ok, state} = send_frame(state, %Frame{frame |
                              flags: %Ping.Flags{ack: true}})
    state
  end

  defp receive_frame(state, %Frame{stream_id: 0, type: :ping,
  flags: %Ping.Flags{ack: false}, payload: %Ping.Payload{}} = frame) do
    Logger.debug "STREAM 0 RECV #{inspect frame}"
    {:ok, state} = send_frame(state, %Frame{
                              type: :goaway,
                              payload: %GoAway.Payload{
                                last_stream_id: state.last_stream_id,
                                error_code: %Error{code: :frame_size_error}}})
    state
  end

  defp receive_frame(state, %Frame{length: 8, type: :ping,
  flags: %Ping.Flags{ack: false}, payload: %Ping.Payload{}} = frame) do
    Logger.debug "STREAM 0 RECV #{inspect frame}"
    {:ok, state} = send_frame(state, %Frame{
                              type: :goaway,
                              payload: %GoAway.Payload{
                                last_stream_id: state.last_stream_id,
                                error_code: %Error{code: :protocol_error}}})
    state
  end

  defp receive_frame(state, %Frame{stream_id: 0, type: :settings,
  flags: %Settings.Flags{ack: false}, payload: %Settings.Payload{}} = frame) do
    Logger.debug "STREAM 0 RECV #{inspect frame}"
    {:ok, state} = send_frame(state, %Frame{frame|
                              flags: %Settings.Flags{ack: true}, payload: nil})
    state
  end

  defp receive_frame(state, %Frame{stream_id: 0} = frame) do
    Logger.debug "STREAM 0 RECV #{inspect frame}"
    state
  end

  defp receive_frame(%{streams: streams} = state, %Frame{stream_id: id} = frame)
  do
    stream = Map.get(streams, id)
    Logger.debug "STREAM #{id} RECV #{inspect frame}"
    {:ok, stream} = Http2.Stream.received_frame(stream, frame)
    Logger.debug "STREAM #{id} IS #{inspect stream}"
    %{state | streams: Map.put(streams, id, stream), last_stream_id: id}
  end

  defp receive_frame(state, _), do: state

  defp parse_frames(<<payload_length::24, _::binary>> = data, state)
  when @frame_header_size + payload_length > byte_size(data) do
    {%{state | buffer: data}, []}
  end

  defp parse_frames(<<payload_length::24, _::binary>> = data, state) do
    frame_size = @frame_header_size + payload_length
    frame_data = binary_part(data, 0, frame_size)
    rest_size = byte_size(data) - frame_size
    rest_data = binary_part(data, frame_size, rest_size)

    {state, frame} = %Frame{}
    |> Encoder.decode!(frame_data, [])
    |> decode_headers(state)

    {state, frames} = parse_frames(rest_data, state)
    {state, [frame | frames]}
  end

  defp parse_frames(_, state), do: {%{state | buffer: <<>>}, []}

  defp decode_headers(%Frame{stream_id: id, type: :headers,
  flags: %Headers.Flags{end_headers: false}, payload: payload} = frame,
  %{streams: streams} = state) do
    stream = Map.get(streams, id)
    stream = %{stream | hbf: stream.hbf <> payload.hbf}
    frame = %{frame | payload: %{payload | header_block_fragment: nil}}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_headers(%Frame{stream_id: id, type: :push_promise,
  flags: %PushPromise.Flags{end_headers: false}, payload: payload} = frame,
  %{streams: streams} = state) do
    stream = Map.get(streams, id)
    stream = %{stream | hbf: stream.hbf <> payload.hbf}
    frame = %{frame | payload: %{payload | header_block_fragment: nil}}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_headers(%Frame{stream_id: id, type: :continuation,
  flags: %Continuation.Flags{end_headers: false}, payload: payload} = frame,
  %{streams: streams} = state) do
    stream = Map.get(streams, id)
    stream = %{stream | hbf: stream.hbf <> payload.hbf}
    frame = %{frame | payload: %{payload | header_block_fragment: nil}}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_headers(%Frame{stream_id: id, type: :headers,
  flags: %Headers.Flags{end_headers: true}, payload: payload} = frame,
  %{streams: streams, recv_hpack_ctx: hpack} = state) do
    hbf = HPack.decode(payload.header_block_fragment, hpack)
    frame = %{frame | payload: %{payload | header_block_fragment: hbf}}
    stream = %{Map.get(streams, id) | hbf: nil}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_headers(%Frame{stream_id: id, type: :push_promise,
  flags: %PushPromise.Flags{end_headers: true}, payload: payload} = frame,
  %{streams: streams, recv_hpack_ctx: hpack} = state) do
    hbf = HPack.decode(payload.header_block_fragment, hpack)
    frame = %{frame | payload: %{payload | header_block_fragment: hbf}}
    stream = %{Map.get(streams, id) | hbf: nil}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_headers(%Frame{stream_id: id, type: :continuation,
  flags: %Continuation.Flags{end_headers: true}, payload: payload} = frame,
  %{streams: streams, recv_hpack_ctx: hpack} = state) do
    hbf = HPack.decode(payload.header_block_fragment, hpack)
    frame = %{frame | payload: %{payload | header_block_fragment: hbf}}
    stream = %{Map.get(streams, id) | hbf: nil}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_headers(frame, state), do: {state, frame}
end
