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
  alias Ankh.{Error, Frame, Stream, Transport}
  alias Ankh.Frame.{GoAway, Settings}
  alias HPack.Table

  require Logger

  @max_window_size 2_147_483_647
  @max_stream_id 2_147_483_647
  @recv_settings [
    header_table_size: 4_096,
    enable_push: true,
    max_concurrent_streams: 128,
    initial_window_size: 2_147_483_647,
    max_frame_size: 16_384,
    max_header_list_size: 128
  ]

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

  """
  @type args :: [uri: URI.t()]

  @doc """
  Start the connection process for the specified `URI`.

  Parameters:
    - args: startup options
    - options: GenServer startup options
  """
  @spec start_link(URI.t()) :: GenServer.on_start()
  def start_link(uri) do
    GenServer.start_link(__MODULE__, Keyword.put([uri: uri], :controlling_process, self()))
  end

  @doc false
  def init(args) do
    transport = Keyword.get(args, :transport, Transport.TLS)
    controlling_process = Keyword.get(args, :controlling_process)
    uri = Keyword.get(args, :uri)
    options = Keyword.get(args, :options, [])
    recv_settings = Keyword.get(args, :settings, @recv_settings)

    with {:ok, send_hpack} <- Table.start_link(4_096),
         header_table_size <- Keyword.get(recv_settings, :header_table_size),
         {:ok, recv_hpack} <- Table.start_link(header_table_size) do
      {:ok,
       %{
         controlling_process: controlling_process,
         last_stream_id: nil,
         options: options,
         receiver: nil,
         recv_hpack: recv_hpack,
         recv_settings: recv_settings,
         send_hpack: send_hpack,
         send_settings: nil,
         socket: nil,
         transport: transport,
         uri: uri,
         window_size: 65_535
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
  def accept(connection, socket, options \\ []),
    do: GenServer.call(connection, {:accept, socket, options})

  @doc """
  Connects to a server
  """
  @spec connect(connection, Keyword.t()) :: :ok | {:error, term}
  def connect(connection, options \\ []), do: GenServer.call(connection, {:connect, options})

  @doc """
  Sends a frame over the connection
  """
  @spec send(connection, Frame.length(), Frame.type(), Frame.data()) :: :ok | {:error, term}
  def send(connection, length, type, data) do
    GenServer.call(connection, {:send, length, type, data})
  end

  def get_stream(connection, id) do
    GenServer.whereis({:via, Registry, {Stream.Registry, {connection, id}}})
  end

  @doc """
  Starts a new stream on the connection
  """
  @spec start_stream(connection, integer | nil, pid | nil) ::
          {:ok, Stream.id(), pid} | {:error, term}
  def start_stream(connection, id \\ nil, controlling_process \\ nil) do
    GenServer.call(connection, {:start_stream, id, controlling_process || self()})
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
  @spec error(connection, Error.t()) :: :ok | {:error, term}
  def error(connection, error), do: GenServer.call(connection, {:error, error})

  def handle_call(
        {:accept, socket, options},
        _from,
        %{
          controlling_process: controlling_process,
          socket: nil,
          transport: transport
        } = state
      ) do
    with {:ok, receiver} <- Receiver.start_link(self(), controlling_process, 2, 1),
         {:ok, socket} <- transport.accept(socket, receiver, options) do
      {:reply, :ok, %{state | last_stream_id: 2, receiver: receiver, socket: socket}}
    else
      {:error, _reason} = error ->
        {:stop, error, error, state}
    end
  end

  def handle_call({:accept, _socket, _options}, _from, state) do
    {:reply, {:error, :connected}, state}
  end

  def handle_call(
        {:connect, options},
        _from,
        %{
          controlling_process: controlling_process,
          recv_settings: recv_settings,
          socket: nil,
          transport: transport,
          uri: uri
        } = state
      ) do
    with {:ok, receiver} <- Receiver.start_link(self(), controlling_process, 1, 2),
         {:ok, socket} <- transport.connect(uri, receiver, options),
         settings <- %Settings{payload: %Settings.Payload{settings: recv_settings}},
         {:ok, _length, _type, data} <- Frame.encode(settings),
         :ok <- transport.send(socket, data) do
      {:reply, :ok,
       %{
         state
         | last_stream_id: 1,
           receiver: receiver,
           socket: socket
       }}
    else
      {:error, _reason} = error ->
        {:stop, error, error, state}
    end
  end

  def handle_call({:connect}, _from, state) do
    {:reply, {:error, :connected}, state}
  end

  def handle_call({:send, _frame}, _from, %{socket: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(
        {:send, length, 0, data},
        _from,
        %{socket: socket, transport: transport, window_size: window_size} = state
      ) do
    with :ok <- transport.send(socket, data) do
      {:reply, :ok, %{state | window_size: window_size - length}}
    else
      error ->
        {:reply, error, state}
    end
  end

  def handle_call(
        {:send, _length, _type, data},
        _from,
        %{socket: socket, transport: transport} = state
      ) do
    with :ok <- transport.send(socket, data) do
      {:reply, :ok, state}
    else
      error ->
        {:reply, error, state}
    end
  end

  def handle_call(
        {:error, error},
        _from,
        %{last_stream_id: last_stream_id, socket: socket, transport: transport} = state
      ) do
    frame = %GoAway{
      payload: %GoAway.Payload{
        last_stream_id: last_stream_id - 2,
        error_code: error
      }
    }

    with {:ok, _length, _type, data} when not is_nil(socket) <- Frame.encode(frame),
         :ok <- transport.send(socket, data) do
      Logger.debug(fn -> "SENT #{inspect(frame)}" end)
    else
      error ->
        Logger.debug(fn -> "ERROR #{inspect(error)} SENDING GOAWAY #{inspect(frame)}" end)
    end

    {:reply, :ok, state}
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
          send_settings: send_settings
        } = state
      ) do
    with max_frame_size <- Keyword.get(send_settings || [], :max_frame_size, 16_384),
         {:ok, pid} <-
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
          send_settings: send_settings
        } = state
      ) do
    with max_frame_size <- Keyword.get(send_settings || [], :max_frame_size, 16_384),
         {:ok, pid} <-
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
        {:send_settings, %Settings.Payload{settings: settings}},
        _from,
        %{
          recv_settings: recv_settings,
          send_hpack: send_hpack,
          send_settings: nil,
          socket: socket,
          transport: transport
        } = state
      ) do
    with header_table_size <- Keyword.get(settings, :header_table_size, 4_096),
         window_size <- Keyword.get(settings, :window_size, 65_535),
         enable_push <- Keyword.get(settings, :enable_push, true),
         :ok <- Table.resize(header_table_size, send_hpack),
         recv_settings <- %Settings.Payload{
           settings: Keyword.put(recv_settings, :enable_push, enable_push)
         },
         {:ok, _length, _type, data} <- Frame.encode(%Settings{payload: recv_settings}),
         :ok <- transport.send(socket, data) do
      {:reply, :ok,
       %{
         state
         | send_hpack: send_hpack,
           window_size: window_size,
           send_settings: settings
       }}
    else
      error ->
        {:reply, error, state}
    end
  end

  def handle_call(
        {:send_settings, %Settings.Payload{settings: settings}},
        _from,
        %{send_hpack: send_hpack} = state
      ) do
    header_table_size = Keyword.get(settings, :header_table_size)

    if header_table_size do
      :ok = Table.resize(header_table_size, send_hpack)
    end

    window_size = Keyword.get(settings, :initial_window_size, 65_535)
    {:reply, :ok, %{state | send_settings: settings, window_size: window_size}}
  end

  def handle_call(
        {:window_update, increment},
        _from,
        %{
          last_stream_id: last_stream_id,
          socket: socket,
          transport: transport,
          window_size: window_size
        } = state
      )
      when window_size + increment > @max_window_size do
    reason = :flow_control_error

    frame = %GoAway{
      payload: %GoAway.Payload{
        last_stream_id: last_stream_id - 2,
        error_code: reason
      }
    }

    with {:ok, _lenght, _type, data} when not is_nil(socket) <- Frame.encode(frame),
         :ok <- transport.send(socket, data) do
      Logger.debug(fn -> "SENT #{inspect(frame)}" end)
    else
      error ->
        Logger.debug(fn -> "ERROR #{inspect(error)} SENDING GOAWAY #{inspect(frame)}" end)
    end

    {:stop, {:error, reason}, state}
  end

  def handle_call(
        {:window_update, increment},
        _from,
        %{window_size: window_size} = state
      ) do
    {:reply, :ok, %{state | window_size: window_size + increment}}
  end
end
