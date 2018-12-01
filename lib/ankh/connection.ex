defmodule Ankh.Connection do
  @moduledoc """
  Genserver implementing HTTP/2 connection management

  `Ankh.Connection` establishes the underlying TLS connection and provides
  connection and stream management, it also does frame (de)serialization and
  reassembly as needed.

  After starting the connection, received frames are sent back to the caller,
  or the process specified in the `controlling_process` startup option, as messages.
  Separate messages are sent for HEADERS, PUSH_PROMISE and DATA frames.

  Headers are always reassembled and sent back in one message to the controlling_process.
  For data frames, the `stream` startup otion toggles streaming mode:

  If `true` (streaming mode) a `stream_data` msg is sent for each received DATA
  frame, and it is the controlling_process responsibility to reassemble incoming data.

  If `false` (full mode), DATA frames are accumulated until a complete response
  is received and then the complete data is sent to the controlling_process as `data` msg.

  See typespecs below for message types and formats.
  """

  use GenServer

  require Logger

  alias Ankh.Connection.Receiver
  alias Ankh.{Frame, Stream}
  alias Ankh.Frame.{GoAway, Settings}
  alias HPack.Table

  @default_ssl_opts binary: true,
                    active: false,
                    versions: [:"tlsv1.2"],
                    secure_renegotiate: true,
                    client_renegotiation: false,
                    ciphers: ["ECDHE-ECDSA-AES128-SHA256", "ECDHE-ECDSA-AES128-SHA"],
                    alpn_advertised_protocols: ["h2"],
                    cacerts: :certifi.cacerts()

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  # @max_stream_id 2_147_483_647

  @typedoc "Connection process"
  @type connection :: GenServer.server()

  @typedoc """
  Ankh DATA message (full mode)

  `{:ankh, :data, stream_id, data}`
  """
  @type data_msg :: {:ankh, :data, Integer.t(), binary}

  @typedoc """
  Ankh DATA frame (streaming mode)

  `{:ankh, :stream_data, stream_id, data}`
  """
  @type streaming_data_msg :: {:ankh, :stream_data, Integer.t(), binary}

  @typedoc """
  Ankh HEADERS message

  `{:ankh, :headers, stream_id, headers}`
  """
  @type headers_msg :: {:ankh, :headers, Integer.t(), Keyword.t()}

  @typedoc """
  Ankh PUSH_PROMISE message

  `{:ankh, :headers, stream_id, promised_stream_id, headers}`
  """
  @type push_promise_msg :: {:ankh, :push_promise, Integer.t(), Integer.t(), Keyword.t()}

  @typedoc """
  Startup options:
    - controlling_process: pid of the process to send received frames to.
    Messages are shipped to the calling process if nil.
    - ssl_options: SSL connection options, for the Erlang `:ssl` module
  """
  @type args :: [uri: URI.t(), controlling_process: pid | nil, ssl_options: Keyword.t()]

  @doc """
  Start the connection process for the specified `URI`.

  Parameters:
    - args: startup options
    - options: GenServer startup options
  """
  @spec start_link(args, GenServer.options()) :: GenServer.on_start()
  def start_link(args, options \\ []) do
    {_, args} =
      Keyword.get_and_update(args, :controlling_process, fn
        nil ->
          {self(), self()}

        value ->
          {value, value}
      end)

    GenServer.start_link(__MODULE__, args, options)
  end

  @doc false
  def init(args) do
    controlling_process = Keyword.get(args, :controlling_process)
    settings = Keyword.get(args, :settings, %Settings.Payload{})
    uri = Keyword.get(args, :uri)
    ssl_opts = Keyword.get(args, :ssl_options, [])

    with %{header_table_size: header_table_size} <- settings,
         {:ok, send_hpack} <- Table.start_link(header_table_size),
         {:ok, recv_hpack} <- Table.start_link(header_table_size),
         {:ok, receiver} <- Receiver.start_link(uri: uri) do
      {:ok,
       %{
         controlling_process: controlling_process,
         last_stream_id: 0,
         uri: uri,
         ssl_opts: ssl_opts,
         receiver: receiver,
         socket: nil,
         recv_hpack: recv_hpack,
         recv_settings: settings,
         send_hpack: send_hpack,
         send_settings: settings,
         window_size: 0
       }}
    else
      error ->
        {:error, error}
    end
  end

  @doc """
  Connects to a server
  """
  @spec connect(connection) :: GenServer.on_call()
  def connect(connection), do: GenServer.call(connection, {:connect})

  @doc """
  Sends a frame over the connection
  """
  @spec send(connection, Frame.t()) :: GenServer.on_call()
  def send(connection, frame) do
    GenServer.call(connection, {:send, frame})
  end

  @doc """
  Starts a new stream on the connection
  """
  @spec start_stream(connection, Stream.mode()) :: GenServer.on_call()
  def start_stream(connection, mode) do
    GenServer.call(connection, {:start_stream, mode})
  end

  @doc """
  Updates send settings for the connection
  """
  @spec send_settings(connection, Settings.Payload.t()) :: GenServer.on_call()
  def send_settings(connection, settings) do
    GenServer.call(connection, {:send_settings, settings})
  end

  @doc """
  Updates the connection window_size with the provided increment
  """
  @spec window_update(connection, Integer.t()) :: GenServer.on_call()
  def window_update(connection, increment) do
    GenServer.call(connection, {:window_update, increment})
  end

  @doc """
  Closes the connection

  Before closing the TLS connection a GOAWAY frame is sent to the peer.
  """
  @spec close(connection) :: :closed
  def close(connection), do: GenServer.call(connection, {:close})

  def handle_call(
        {:connect},
        _from,
        %{
          socket: nil,
          ssl_opts: ssl_opts,
          uri: %URI{host: host, port: port},
          recv_settings: recv_settings,
          receiver: receiver
        } = state
      ) do
    hostname = String.to_charlist(host)
    ssl_options = Keyword.merge(ssl_opts, @default_ssl_opts)

    with {:ok, socket} <- :ssl.connect(hostname, port, ssl_options),
         :ok <- :ssl.controlling_process(socket, receiver),
         :ok <- :ssl.setopts(socket, active: :once),
         :ok <- :ssl.send(socket, @preface),
         :ok <- :ssl.send(socket, Frame.encode!(%Settings{payload: recv_settings})) do
      {:reply, :ok, %{state | socket: socket}}
    else
      error ->
        {:stop, :error, :ssl.format_error(error), state}
    end
  end

  def handle_call({:connect}, _from, state) do
    {:reply, {:error, :connected}, state}
  end

  def handle_call({:send, _frame}, _from, %{socket: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send, frame}, _from, %{socket: socket} = state) do
    Logger.debug("Sending #{inspect frame}")
    case :ssl.send(socket, Frame.encode!(frame)) do
      :ok ->
        {:reply, :ok, state}

      error ->
        {:stop, :ssl.format_error(error), state}
    end
  end

  def handle_call({:close}, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(
        {:start_stream, mode},
        _from,
        %{
          controlling_process: controlling_process,
          last_stream_id: last_stream_id,
          recv_hpack: recv_hpack,
          send_hpack: send_hpack,
          send_settings: %{max_frame_size: max_frame_size}
        } = state
      ) do
    stream_id = last_stream_id + 1

    {:ok, pid} =
      Stream.start_link(
        self(),
        stream_id,
        recv_hpack,
        send_hpack,
        max_frame_size,
        controlling_process,
        mode
      )

    {:reply, {:ok, pid}, %{state | last_stream_id: stream_id}}
  end

  def handle_call(
        {:send_settings,
         %{header_table_size: header_table_size, initial_window_size: window_size} = send_settings},
        _from,
        %{send_hpack: send_hpack} = state
      ) do
    :ok = Table.resize(header_table_size, send_hpack)
    {:reply, :ok, %{state | send_settings: send_settings, window_size: window_size}}
  end

  def handle_call(
        {:window_update, increment},
        _from,
        %{window_size: window_size} = state
      ) do
    {:reply, :ok, %{state | window_size: window_size + increment}}
  end

  def terminate(reason, %{socket: nil, receiver: receiver}) do
    Logger.error("Connection terminate: #{inspect(reason)}")
    GenServer.stop(receiver)
  end

  def terminate(reason, %{socket: socket, last_stream_id: last_stream_id} = state) do
    :ssl.send(
      socket,
      Frame.encode!(%GoAway{
        payload: %GoAway.Payload{
          last_stream_id: last_stream_id,
          error_code: :no_error
        }
      })
    )

    :ssl.close(socket)
    terminate(reason, %{state | socket: nil})
  end
end
