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

  alias Ankh.Frame
  alias Ankh.Frame.Encoder
  alias Ankh.Connection.Receiver

  @default_ssl_opts binary: true,
                    active: false,
                    versions: [:"tlsv1.2"],
                    secure_renegotiate: true,
                    client_renegotiation: false,
                    ciphers: ["ECDHE-ECDSA-AES128-SHA256", "ECDHE-ECDSA-AES128-SHA"],
                    alpn_advertised_protocols: ["h2"],
                    cacerts: :certifi.cacerts()

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  @typedoc """
  Ankh Connection process
  """
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

  def init(args) do
    controlling_process = Keyword.get(args, :controlling_process)
    uri = Keyword.get(args, :uri)
    ssl_opts = Keyword.get(args, :ssl_options, [])

    with {:ok, receiver} <-
           Receiver.start_link(uri: uri, controlling_process: controlling_process) do
      {:ok, %{uri: uri, ssl_opts: ssl_opts, receiver: receiver, socket: nil}}
    else
      error ->
        {:error, error}
    end
  end

  @doc """
  Connects to a server via the specified URI

  Parameters:
    - connection: connection process
    - uri: The server to connect to, scheme and authority are used
  """
  @spec connect(connection) :: :ok | {:error, atom}
  def connect(connection), do: GenServer.call(connection, {:connect})

  @doc """
  Sends a frame over the connection

  Parameters:
    - connection: connection process
    - frame: `Ankh.Frame` structure
  """
  @spec send(connection, Frame.t()) :: :ok | {:error, atom}
  def send(connection, frame) do
    GenServer.call(connection, {:send, Encoder.encode!(frame, [])})
  end

  @doc """
  Closes the connection

  Before closing the TLS connection a GOAWAY frame is sent to the peer.

  Parameters:
    - connection: connection process
  """
  @spec close(connection) :: :closed
  def close(connection), do: GenServer.call(connection, {:close})

  def handle_call(
        {:connect},
        _from,
        %{socket: nil, ssl_opts: ssl_opts, uri: %URI{host: host, port: port}, receiver: receiver} =
          state
      ) do
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

  def handle_call({:connect}, _from, state) do
    {:reply, {:error, :connected}, state}
  end

  def handle_call({:send, _frame}, _from, %{socket: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send, frame}, _from, %{socket: socket} = state) do
    case :ssl.send(socket, frame) do
      :ok ->
        {:reply, :ok, state}

      error ->
        {:stop, :ssl.format_error(error), state}
    end
  end

  def handle_call({:close}, _from, state) do
    {:stop, :shutdown, state}
  end

  def terminate(_reason, %{socket: nil, receiver: receiver}) do
    GenServer.stop(receiver)
  end

  def terminate(reason, %{socket: socket} = state) do
    :ssl.close(socket)
    terminate(reason, %{state | socket: nil})
  end
end
