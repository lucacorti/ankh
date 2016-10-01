defmodule Ankh.Connection do
  @moduledoc """
  Genserver implementing HTTP/2 connection management

  `Ankh.Connection` establishes the TLS underlying connection and provides
  connection and stream management, it also does frame (de)serialization and
  reassembly as needed.

  After starting the connection, received frames are sent back to the caller,
  or the process specified in the `receiver` startup option, as messages.
  See typespecs below for message types and formats.
  """

  use GenServer

  alias Ankh.{Frame, Stream}
  alias Ankh.Frame.{Encoder, Error, GoAway, Ping, Settings}

  require Logger

  @default_ssl_opts binary: true, versions: [:"tlsv1.2"],
  secure_renegotiate: true, alpn_advertised_protocols: ["h2"],
  client_renegotiation: false,
  ciphers: ["ECDHE-ECDSA-AES128-SHA256", "ECDHE-ECDSA-AES128-SHA"]
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @frame_header_size 9
  @max_stream_id 2_147_483_648

  @typedoc """
  Ankh DATA message (full mode)

  `{:ankh, :data, stream_id, data}`
  """
  @type data_msg :: {:ankh, :data, Integer.t, binary}

  @typedoc """
  Ankh DATA frame (streaming mode)

  `{:ankh, :stream_data, stream_id, data}`
  """
  @type streaming_data_msg :: {:ankh, :stream_data, Integer.t, binary}

  @typedoc """
  Ankh HEADERS message

  `{:ankh, :headers, stream_id, headers}`
  """
  @type headers_msg :: {:ankh, :headers, Integer.t, Keyword.t}

  @typedoc """
  Ankh PUSH_PROMISE message

  `{:ankh, :headers, stream_id, promised_stream_id, headers}`
  """
  @type push_promise_msg :: {:ankh, :push_promise, Integer.t, Integer.t, Keyword.t}

  @typedoc """
  Startup options:
    - uri: at least scheme and authority must be present.
    - receiver: pid of the process to send response messages to.
    Messages are shipped to the calling process if nil.
    - stream: if true, stream received data frames back to the
    receiver, else reassemble and send complete responses.
    - ssl_options: SSL connection options, for the Erlang `:ssl` module
  """
  @type options :: [uri: URI.t, receiver: pid | nil, stream: boolean,
  ssl_options: Keyword.t]

  @doc """
  Start the connection process for the specified `URI`.

  Parameters:
    - args: startup options
    - options: GenServer startup options
  """
  @spec start_link([uri: URI, receiver: pid | nil, stream: boolean,
  ssl_options: Keyword.t], GenServer.option) :: GenServer.on_start
  def start_link([uri: uri, receiver: receiver, stream: stream,
  ssl_options: ssl_options], options \\ []) do
    target = if is_pid(receiver), do: receiver, else: self()
    mode = if is_boolean(stream) && stream, do: :stream, else: :full
    GenServer.start_link(__MODULE__, [uri: uri, target: target, mode: mode,
    ssl_options: ssl_options], options)
  end

  def init([uri: uri, target: target, mode: mode, ssl_options: ssl_opts]) do
    with settings <- %Settings.Payload{},
         {:ok, recv_ctx} = HPack.Table.start_link(settings.header_table_size),
         {:ok, send_ctx} = HPack.Table.start_link(settings.header_table_size) do
      {:ok, %{uri: uri, target: target, mode: mode, ssl_opts: ssl_opts,
      socket: nil, streams: %{}, last_stream_id: 0, buffer: <<>>,
      recv_ctx: recv_ctx, send_ctx: send_ctx, recv_settings: settings,
      send_settings: nil, window_size: 65_535}}
    end
  end

  @doc """
  Sends a frame over the connection

  Parameters:
    - connection: pid or process name of the `Ankh.Connection` process
    - frame: `Ankh.Frame` structure
  """
  @spec send(pid() | :atom, Frame.t) :: :ok | {:error, atom}
  def send(connection, %Frame{} = frame) do
    GenServer.call(connection, {:send, frame})
  end

  @doc """
  Closes the connection

  Before closing the TLS connection a GOAWAY frame is sent to the peer.

  Parameters:
    - connection: pid or process name of the `Ankh.Connection` process
  """
  @spec close(pid() | :atom) :: :closed
  def close(connection), do: GenServer.call(connection, {:close})

  def handle_call({:send, frame}, from, %{socket: nil, uri: %URI{host: host,
  port: port}, ssl_opts: ssl_opts} = state) do
    hostname = String.to_charlist(host)
    ssl_options = Keyword.merge(ssl_opts, @default_ssl_opts)
    with {:ok, socket} <- :ssl.connect(hostname, port, ssl_options),
         :ok <- :ssl.send(socket, @preface) do
      state = %{state | socket: socket}
      handle_call({:send, %Frame{type: :settings, stream_id: 0,
      flags: %Settings.Flags{}, payload: %Settings.Payload{}}}, from, state)
      handle_call({:send, frame}, from, state)
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

  def handle_call({:close}, _from, %{socket: socket,
  last_stream_id: last_stream_id} = state) do
    __MODULE__.send(self(), %Frame{stream_id: 0, type: :goaway,
    payload: %GoAway.Payload{last_stream_id: last_stream_id,
    error_code: %Error{code: :no_error}}})
    :ok = :ssl.close(socket)
    {:stop, :closed, state}
  end

  def handle_info({:ssl, _socket, data}, %{buffer: buffer} = state) do
    {state, frames} = buffer <> data
    |> parse_frames(state)

    state = frames
    |> Enum.reduce(state, fn
      %{stream_id: id} = frame, %{streams: streams} = state ->
        receive_frame(state, Map.get(streams, id), frame)
    end)

    {:noreply, state}
  end

  def handle_info({:ssl_closed, _socket}, state) do
    {:stop, :closed, state}
  end

  def handle_info({:ssl_error, _socket, reason}, state) do
    {:stop, reason, state}
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

  defp send_frame(%{socket: socket, streams: streams} = state,
  %Frame{stream_id: id} = frame) do
    stream = Map.get(streams, id, Stream.new(id, :idle))
    Logger.debug "STREAM #{id} SEND #{inspect frame}"
    {:ok, stream} = Stream.send_frame(stream, frame)
    Logger.debug "STREAM #{id} IS #{inspect stream}"

    {state, stream, frame} = frame
    |> encode_frame(stream, state)

    case :ssl.send(socket, Encoder.encode!(frame, [])) do
      :ok ->
        {:ok, %{state | streams: Map.put(streams, id, stream)}}
      error ->
        :ssl.format_error(error)
    end
  end

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
    |> decode_frame(state)

    {state, frames} = parse_frames(rest_data, state)
    {state, [frame | frames]}
  end

  defp parse_frames(_, state), do: {%{state | buffer: <<>>}, []}

  defp encode_frame(%Frame{type: :headers, payload:
  %{header_block_fragment: headers} = payload} = frame,
  stream,
  %{send_ctx: hpack} = state) do
    hbf = HPack.encode(headers, hpack)
    {state, stream, %{frame | payload: %{payload | header_block_fragment: hbf}}}
  end

  defp encode_frame(%Frame{type: :push_promise, payload:
  %{header_block_fragment: headers} = payload} = frame,
  stream,
  %{send_ctx: hpack} = state) do
    hbf = HPack.encode(headers, hpack)
    {state, %{stream| state: :reserved_local},
    %{frame | payload: %{payload | header_block_fragment: hbf}}}
  end

  defp encode_frame(frame, stream, state) do
    {state, stream, frame}
  end

  defp receive_frame(state, _stream,
  %Frame{stream_id: 0, type: :ping, length: 8, flags: %{ack: false}} = frame) do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    {:ok, state} = send_frame(state, %Frame{frame |
      flags: %Ping.Flags{ack: true}
    })
    state
  end

  defp receive_frame(%{last_stream_id: id} = state, _stream,
  %Frame{stream_id: 0, type: :ping,flags: %{ack: false}} = frame) do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    {:ok, state} = send_frame(state, %Frame{
      type: :goaway, payload: %GoAway.Payload{
        last_stream_id: id, error_code: %Error{code: :frame_size_error}
      }
    })
    state
  end

  defp receive_frame(%{last_stream_id: id} = state, _stream,
  %Frame{length: 8, type: :ping, flags: %{ack: false}} = frame) do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    {:ok, state} = send_frame(state, %Frame{
      type: :goaway, payload: %GoAway.Payload{
        last_stream_id: id, error_code: %Error{code: :protocol_error}
      }
    })
    state
  end

  defp receive_frame(%{send_ctx: table} = state, _stream,
  %Frame{stream_id: 0, type: :settings, flags: %{ack: false},
  payload: %{header_table_size: table_size} = payload} = frame)
  do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    {:ok, state} = send_frame(state, %Frame{frame|
      flags: %Settings.Flags{ack: true}, payload: nil
    })
    :ok = HPack.Table.resize(table_size, table)
    %{state | send_settings: payload}
  end

  defp receive_frame(state, _stream,
  %Frame{stream_id: 0, type: :settings, flags: %{ack: true}, length: 0} = frame)
  do
    Logger.debug "STREAM 0 RECEIVED #{inspect frame}"
    state
  end

  defp receive_frame(state, _stream, %Frame{stream_id: id, type: :window_update,
  payload: %{window_size_increment: increment}})
  when not is_integer(increment) or increment <= 0 do
    Logger.debug "STREAM #{id} ERROR window_size_increment #{increment}"
    {:ok, state} = send_frame(state, %Frame{
      type: :goaway, payload: %GoAway.Payload{
        last_stream_id: id, error_code: %Error{code: :protocol_error}
      }
    })
    state
  end

  defp receive_frame(state, _stream, %Frame{stream_id: 0, type: :window_update,
  payload: %{window_size_increment: increment}}) do
    Logger.debug "STREAM 0 window_size_increment #{increment}"
    %{state | window_size: state.window_size + increment}
  end

  defp receive_frame(%{streams: streams} = state, stream, %Frame{stream_id: id,
  type: :window_update, payload: %{window_size_increment: increment}}) do
    Logger.debug "STREAM #{id} window_size_increment #{increment}"
    stream = %{stream | window_size: stream.window_size + increment}
    %{state | streams: Map.put(streams, id, stream)}
  end

  defp receive_frame(state, _stream, %Frame{stream_id: 0, type: :goaway,
  payload: %{error_code: %{code: code}}} = frame) do
    Logger.debug "STREAM 0 RECEIVED FRAME #{inspect frame}"
    {:stop, code, state}
  end

  defp receive_frame(state, _stream, %Frame{stream_id: 0} = frame) do
    Logger.error "STREAM 0 RECEIVED UNHANDLED FRAME #{inspect frame}"
    state
  end

  defp receive_frame(%{streams: streams} = state, stream,
  %Frame{stream_id: id} = frame) do
    Logger.debug "STREAM #{id} RECEIVED #{inspect frame}"
    {:ok, stream} = Stream.received_frame(stream, frame)
    Logger.debug "STREAM #{id} IS #{inspect stream}"
    %{state | streams: Map.put(streams, id, stream), last_stream_id: id}
  end

  defp decode_frame(%Frame{stream_id: 0} = frame, state), do: {state, frame}

  defp decode_frame(%Frame{stream_id: id, type: :headers,
  flags: %{end_headers: false}, payload: %{header_block_fragment: hbf}} = frame,
  %{streams: streams} = state) do
    Logger.debug("STREAM #{id} RECEIVED PARTIAL HBF #{inspect hbf}")
    stream = Map.get(streams, id)
    stream = %{stream | hbf: stream.hbf <> hbf}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_frame(%Frame{stream_id: id, type: :push_promise,
  flags: %{end_headers: false}, payload: %{promised_stream_id: promised_id,
  header_block_fragment: hbf}} = frame,
  %{streams: streams} = state) do
    Logger.debug("STREAM #{id} RECEIVED PARTIAL HBF #{inspect hbf}")
    stream = Map.get(streams, id)

    stream = %{stream | promised_id: promised_id, hbf_type: :push_promise,
    hbf: stream.hbf <> hbf}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_frame(%Frame{stream_id: id, type: :continuation,
  flags: %{end_headers: false}, payload: %{header_block_fragment: hbf}} = frame,
  %{streams: streams} = state) do
    Logger.debug("STREAM #{id} RECEIVED PARTIAL HBF #{inspect hbf}")
    stream = Map.get(streams, id)
    stream = %{stream | hbf: stream.hbf <> hbf}
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_frame(%Frame{stream_id: id, type: :headers,
  flags: %{end_headers: true}, payload: %{header_block_fragment: hbf}} = frame,
  %{streams: streams, recv_ctx: table, target: target} = state) do
    stream = Map.get(streams, id)
    headers = HPack.decode(stream.hbf <> hbf, table)
    Logger.debug("STREAM #{id} RECEIVED HEADERS #{inspect headers}")
    Process.send(target, {:ankh, :headers, id, headers}, [])
    {%{state | streams: Map.put(streams, id, %{stream | hbf: <<>>})}, frame}
  end

  defp decode_frame(%Frame{stream_id: id, type: :push_promise,
  flags: %{end_headers: true}, payload: %{promised_stream_id: promised_id,
  header_block_fragment: hbf}} = frame,
  %{streams: streams, recv_ctx: table, target: target} = state) do
    stream = Map.get(streams, id)
    headers = HPack.decode(stream.hbf <> hbf, table)
    Logger.debug("STREAM #{id} RECEIVED HEADERS #{inspect headers}")
    Process.send(target, {:ankh, :push_promise, id, promised_id, headers}, [])
    streams = streams
    |> Map.put(id, %{stream | hbf: <<>>})
    |> Map.put(promised_id, Stream.new(promised_id, :reserved_remote))
    {%{state | streams: streams}, frame}
  end

  defp decode_frame(%Frame{stream_id: id, type: :continuation,
  flags: %{end_headers: true}, payload: %{header_block_fragment: hbf}} = frame,
  %{streams: streams, recv_ctx: table, target: target} = state) do
    stream = Map.get(streams, id)
    headers = HPack.decode(stream.hbf <> hbf, table)
    Logger.debug("STREAM #{id} RECEIVED HEADERS #{inspect headers}")
    Process.send(target, {:ankh, stream.hbf_type, id, headers}, [])
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

  defp decode_frame(%Frame{stream_id: id, type: :data,
  flags: %{end_stream: false}, payload: %{data: data}} = frame,
  %{streams: streams, target: target, mode: mode} = state) do
    stream = Map.get(streams, id)
    stream = %{stream | data: stream.data <> data}
    case mode do
      :stream ->
        Process.send(target, {:ankh, :stream_data, id, data}, [])
      _ ->
        Logger.debug("Full mode, not sending partial data")
    end
    {%{state | streams: Map.put(streams, id, stream)}, frame}
  end

  defp decode_frame(%Frame{stream_id: id, type: :data,
  flags: %{end_stream: true}, payload: %{data: data}} = frame,
  %{streams: streams, target: target, mode: mode} = state) do
    stream = Map.get(streams, id)
    data = stream.data <> data
    Logger.debug("STREAM #{id} RECEIVED #{byte_size data} BYTES DATA:\n#{data}")
    case {mode, stream.data} do
      {:full, _} ->
        Process.send(target, {:ankh, :data, id, data}, [])
      {:stream, <<>>} ->
        Process.send(target, {:ankh, :stream_data, id, data}, [])
      _ ->
        Logger.debug("Streaming mode, not sending reassembled data")
    end
    {%{state | streams: Map.put(streams, id, %{stream | data: <<>>})}, frame}
  end

  defp decode_frame(frame, state), do: {state, frame}
end
