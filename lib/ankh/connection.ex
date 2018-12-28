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
  For data frames a `data` msg is sent for each received DATA
  frame, and it is the controlling_process responsibility to reassemble incoming data.

  For both HEADERS and DATA FRAMES the end_stream flag signals if the peer is
  done with the stream or more DATA/HEADERS blocks are going to be transmitted.

  Errors are reported via `error` msg.

  See typespecs below for message types and formats.
  """

  use GenServer

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

  @max_stream_id 2_147_483_647

  @typedoc "Connection process"
  @type connection :: GenServer.server()

  @typedoc """
  Ankh ERROR message

  `{:ankh, :error, stream_id, error}`
  """
  @type error_msg :: {:ankh, :data, integer, term}

  @typedoc """
  Ankh DATA message

  `{:ankh, :data, stream_id, data}`
  """
  @type data_msg :: {:ankh, :data, integer, binary}

  @typedoc """
  Ankh HEADERS message

  `{:ankh, :headers, stream_id, headers}`
  """
  @type headers_msg :: {:ankh, :headers, integer, Keyword.t()}

  @typedoc """
  Ankh PUSH_PROMISE message

  `{:ankh, :headers, stream_id, promised_stream_id, headers}`
  """
  @type push_promise_msg :: {:ankh, :push_promise, integer, integer, Keyword.t()}

  @typedoc """
  Startup options:
    - ssl_options: SSL connection options, for the Erlang `:ssl` module
  """
  @type args :: [uri: URI.t(), ssl_options: Keyword.t()]

  @doc """
  Start the connection process for the specified `URI`.

  Parameters:
    - args: startup options
    - options: GenServer startup options
  """
  @spec start_link(args, GenServer.options()) :: GenServer.on_start()
  def start_link(args, options \\ []) do
    GenServer.start_link(__MODULE__, Keyword.put(args, :controlling_process, self()), options)
  end

  @doc false
  def init(args) do
    settings = Keyword.get(args, :settings, %Settings.Payload{})
    controlling_process = Keyword.get(args, :controlling_process)
    uri = Keyword.get(args, :uri)
    ssl_opts = Keyword.get(args, :ssl_options, [])

    with %{header_table_size: header_table_size} <- settings,
         {:ok, send_hpack} <- Table.start_link(header_table_size),
         {:ok, recv_hpack} <- Table.start_link(header_table_size),
         {:ok, receiver} <- Receiver.start_link(self(), controlling_process) do
      {:ok,
       %{
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
  Accepts a client connection
  """
  @spec accept(connection, pid) :: :ok | {:error, term}
  def accept(connection, socket), do: GenServer.call(connection, {:accept, socket})

  @doc """
  Connects to a server
  """
  @spec connect(connection) :: :ok | {:error, term}
  def connect(connection), do: GenServer.call(connection, {:connect})

  @doc """
  Sends a frame over the connection
  """
  @spec send(connection, Frame.t()) :: :ok | {:error, term}
  def send(connection, frame) do
    GenServer.call(connection, {:send, frame})
  end

  @doc """
  Starts a new stream on the connection
  """
  @spec start_stream(connection, integer | nil, pid | nil) ::
          {:ok, Stream.id(), pid} | {:error, term}
  def start_stream(connection, id \\ nil, controlling_process \\ nil)

  def start_stream(connection, id, controlling_process)
      when is_nil(controlling_process) do
    GenServer.call(connection, {:start_stream, id, self()})
  end

  def start_stream(connection, id, controlling_process) do
    GenServer.call(connection, {:start_stream, id, controlling_process})
  end

  @doc """
  Updates send settings for the connection
  """
  @spec send_settings(connection, Settings.Payload.t()) :: :ok | {:error, term}
  def send_settings(connection, settings) do
    GenServer.call(connection, {:send_settings, settings})
  end

  @doc """
  Updates the connection window_size with the provided increment
  """
  @spec window_update(connection, integer) :: :ok | {:error, term}
  def window_update(connection, increment) do
    GenServer.call(connection, {:window_update, increment})
  end

  @doc """
  Closes the connection

  Before closing the TLS connection a GOAWAY frame is sent to the peer.
  """
  @spec close(connection) :: :ok | {:error, term}
  def close(connection), do: GenServer.call(connection, {:close})

  def handle_call(
        {:accept, socket},
        _from,
        %{
          socket: nil,
          ssl_opts: _ssl_opts,
          send_settings: send_settings,
          receiver: receiver
        } = state
      ) do
    preface = @preface

    with {:ok, ^preface} <- :ssl.recv(socket, 24),
         :ok <- :ssl.controlling_process(socket, receiver),
         :ok <- :ssl.setopts(socket, active: :once),
         :ok <- :ssl.send(socket, Frame.encode!(%Settings{payload: send_settings})) do
      {:reply, :ok, %{state | last_stream_id: 2, socket: socket}}
    else
      {:error, reason} ->
        error = {:error, :ssl.format_error(reason)}
        {:stop, error, error, state}
    end
  end

  def handle_call({:sccept, _socket}, _from, state) do
    {:reply, {:error, :connected}, state}
  end

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
      {:reply, :ok, %{state | last_stream_id: 1, socket: socket}}
    else
      {:error, reason} ->
        error = {:error, :ssl.format_error(reason)}
        {:stop, error, error, state}
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

      {:error, reason} ->
        error = {:error, :ssl.format_error(reason)}
        {:stop, error, error, state}
    end
  end

  def handle_call({:close}, _from, %{last_stream_id: last_stream_id, socket: socket} = state) do
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
    {:stop, :normal, :ok, %{state | socket: nil}}
  end

  def handle_call(
        {:start_stream, id, _controlling_process},
        _from,
        %{last_stream_id: last_stream_id} = state
      )
      when (not is_nil(id) and id >= @max_stream_id) or last_stream_id >= @max_stream_id do
    error = {:error, :stream_limit_reached}
    {:stop, error, error, state}
  end

  def handle_call(
        {:start_stream, nil, controlling_process},
        _from,
        %{
          last_stream_id: last_stream_id,
          recv_hpack: recv_hpack,
          send_hpack: send_hpack,
          send_settings: %{max_frame_size: max_frame_size}
        } = state
      ) do
    with {:ok, pid} <-
           Stream.start_link(
             self(),
             last_stream_id,
             recv_hpack,
             send_hpack,
             max_frame_size,
             controlling_process,
             name: {:via, Registry, {Stream.Registry, {self(), last_stream_id}}}
           ) do
      {:reply, {:ok, last_stream_id, pid}, %{state | last_stream_id: last_stream_id + 2}}
    else
      {:error, {:already_started, pid}} ->
        {:reply, {:ok, last_stream_id, pid}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(
        {:start_stream, id, controlling_process},
        _from,
        %{
          recv_hpack: recv_hpack,
          send_hpack: send_hpack,
          send_settings: %{max_frame_size: max_frame_size}
        } = state
      ) do
    with {:ok, pid} <-
           Stream.start_link(
             self(),
             id,
             recv_hpack,
             send_hpack,
             max_frame_size,
             controlling_process,
             name: {:via, Registry, {Stream.Registry, {self(), id}}}
           ) do
      {:reply, {:ok, id, pid}, state}
    else
      {:error, {:already_started, pid}} ->
        {:reply, {:ok, id, pid}, state}

      error ->
        {:reply, error, state}
    end
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
end
