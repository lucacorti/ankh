defmodule Ankh.Connection do
  @moduledoc """
  Genserver implementing HTTP/2 connection management

  `Ankh.Connection` establishes the underlying TLS connection and provides
  connection and stream management, it also does frame (de)serialization and
  reassembly as needed.

  After starting the connection, received frames are sent back to the caller,
  or the process specified in the `receiver` startup option, as messages.
  Separate messages are sent for HEADERS, PUSH_PROMISE and DATA frames.

  Headers are always reassembled and sent back in one message to the receiver.
  For data frames, the `stream` startup otion toggles streaming mode:

  If `true` (streaming mode) a `stream_data` msg is sent for each received DATA
  frame, and it is the receiver responsibility to reassemble incoming data.

  If `false` (full mode), DATA frames are accumulated until a complete response
  is received and then the complete data is sent to the receiver as `data` msg.

  See typespecs below for message types and formats.
  """

  use GenServer

  alias HPack.Table
  alias Ankh.{Frame, Stream}
  alias Ankh.Connection.Receiver
  alias Ankh.Frame.{Encoder, Goaway, Headers, PushPromise, Settings}

  require Logger

  @default_ssl_opts binary: true, active: false, versions: [:"tlsv1.2"],
  secure_renegotiate: true, client_renegotiation: false,
  ciphers: ["ECDHE-ECDSA-AES128-SHA256", "ECDHE-ECDSA-AES128-SHA"],
  alpn_advertised_protocols: ["h2"]
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  @typedoc """
  Ankh Connection process
  """
  @type connection :: GenServer.server

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
  @type push_promise_msg :: {:ankh, :push_promise, Integer.t, Integer.t,
  Keyword.t}

  @typedoc """
  Startup options:
    - receiver: pid of the process to send response messages to.
    Messages are shipped to the calling process if nil.
    - stream: if true, stream received data frames back to the
    receiver, else reassemble and send complete responses.
    - ssl_options: SSL connection options, for the Erlang `:ssl` module
  """
  @type options :: [receiver: pid | nil, stream: boolean,
  ssl_options: Keyword.t]

  @doc """
  Start the connection process for the specified `URI`.

  Parameters:
    - args: startup options
    - options: GenServer startup options
  """
  @spec start_link([receiver: pid | nil, stream: boolean,
  ssl_options: Keyword.t], GenServer.option) :: GenServer.on_start
  def start_link([receiver: receiver, stream: stream, ssl_options: ssl_options],
  options \\ []) do
    target = if is_pid(receiver), do: receiver, else: self()
    mode = if is_boolean(stream) && stream, do: :stream, else: :full
    GenServer.start_link(__MODULE__, [target: target, mode: mode,
    ssl_options: ssl_options], options)
  end

  def init([target: target, mode: mode, ssl_options: ssl_opts]) do
    settings = %Settings.Payload{}
    with %{header_table_size: header_table_size} <- settings,
        {:ok, send_ctx} <- Table.start_link(header_table_size),
        {:ok, receiver} <- Receiver.start_link(sender: self(), receiver: target,
        mode: mode)
    do
      {:ok, %{mode: mode, ssl_opts: ssl_opts, socket: nil, receiver: receiver,
       send_ctx: send_ctx, send_settings: settings}}
    end
  end

  @doc """
  Connects to a server via the specified URI

  Parameters:
    - connection: connection process
    - uri: The server to connect to, scheme and authority are used
  """
  @spec connect(connection, URI.t) :: :ok | {:error, atom}
  def connect(connection, uri), do: GenServer.call(connection, {:connect, uri})

  @doc """
  Sends a frame over the connection

  Parameters:
    - connection: connection process
    - frame: `Ankh.Frame` structure
  """
  @spec send(connection, Frame.t) :: :ok | {:error, atom}
  def send(connection, frame), do: GenServer.call(connection, {:send, frame})

  @doc """
  Closes the connection

  Before closing the TLS connection a GOAWAY frame is sent to the peer.

  Parameters:
    - connection: connection process
  """
  @spec close(connection) :: :closed
  def close(connection), do: GenServer.call(connection, {:close})

  @doc """
  Update send settings
  """
  @spec update_settings(connection, Settings.Payload.t) :: :ok
  def update_settings(connection, settings) do
    GenServer.call(connection, {:update_settings, settings})
  end

  def handle_call({:connect, %URI{host: host, port: port}}, _from,
  %{socket: nil, ssl_opts: ssl_opts, receiver: receiver} = state) do
    hostname = String.to_charlist(host)
    ssl_options = Keyword.merge(ssl_opts, @default_ssl_opts)
    with {:ok, socket} <- :ssl.connect(hostname, port, ssl_options),
         :ok <- :ssl.controlling_process(socket, receiver),
         :ok <- :ssl.setopts(socket, active: :once),
         :ok <- :ssl.send(socket, @preface) do
      {:reply, :ok, %{state | socket: socket}}
    else
      error ->
        {:stop, :error, :ssl.format_error(error), state}
    end
  end

  def handle_call({:connect, _uri}, _from, state) do
    {:reply, {:error, :connected}, state}
  end

  def handle_call({:send, _frame}, _from, %{socket: nil} = state) do
    {:stop, :shutdown, {:error, :not_connected}, state}
  end

  def handle_call({:send, frame}, _from, state) do
    case send_frame(state, frame) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      error ->
        {:stop, :shutdown, error, state}
    end
  end

  def handle_call({:close}, _from, state) do
    {:stop, :shutdown, :ok, state}
  end

  def handle_call({:update_settings, %{header_table_size: hts} = settings},
  _from, %{send_ctx: table} = state) do
    :ok = Table.resize(hts, table)
    {:reply, :ok, %{state | send_settings: settings}}
  end

  def terminate(_reason, %{receiver: receiver, socket: nil}) do
    :ok = GenServer.stop(receiver)
  end

  def terminate(_reason, %{receiver: receiver, socket: socket} = state) do
    {:ok, lsid} = Receiver.last_stream_id(receiver)
    send_frame(state, %Goaway{stream_id: 0,
    payload: %Goaway.Payload{last_stream_id: lsid, error_code: :no_error}})
    :ok = :ssl.close(socket)
    :ok = GenServer.stop(receiver)
  end

  defp send_frame(%{socket: socket} = state, %{stream_id: 0} = frame) do
    Logger.debug "STREAM 0 SEND #{inspect frame}"
    case :ssl.send(socket, Encoder.encode!(frame, [])) do
      :ok ->
        {:ok, state}
      error ->
        :ssl.format_error(error)
    end
  end

  defp send_frame(%{socket: socket, receiver: receiver, send_ctx: table} = state,
  %{stream_id: id} = frame) do

    with {:ok, stream} = Receiver.stream(receiver, id),
         {:ok, a_stream} <- Stream.send_frame(stream, frame),
         {_stream, frame} <- encode_headers(frame, a_stream, table) do
      Logger.debug "STREAM #{id} SEND #{inspect frame}"
      Logger.debug "STREAM #{id} IS #{inspect stream}"

      case :ssl.send(socket, Encoder.encode!(frame, [])) do
        :ok ->
          :ok = Receiver.update_stream(receiver, id, a_stream)
          {:ok, state}
        error ->
          :ssl.format_error(error)
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_headers(%Headers{payload:
  %{header_block_fragment: headers} = payload} = frame,
  stream, table) do
    hbf = HPack.encode(headers, table)
    {stream, %{frame | payload: %{payload | header_block_fragment: hbf}}}
  end

  defp encode_headers(%PushPromise{payload:
  %{header_block_fragment: headers} = payload} = frame,
  stream, table) do
    hbf = HPack.encode(headers, table)
    {%{stream| state: :reserved_local},
    %{frame | payload: %{payload | header_block_fragment: hbf}}}
  end

  defp encode_headers(frame, stream, _table) do
    {stream, frame}
  end
end
