defmodule Ankh.Transport.QUIC do
  @moduledoc """
  QUIC transport implementation using the `quicer` library.

  This transport uses `quicer` (https://github.com/emqx/quic), an Erlang/Elixir
  binding for MsQuic — Microsoft's cross-platform QUIC implementation.

  ## Differences from TCP/TLS

  Unlike TCP or TLS transports, which expose a single bytestream socket, QUIC is
  inherently multiplexed. The QUIC transport therefore manages two distinct handles:

    * A **connection handle** (`t:connection/0`) — the underlying QUIC connection.
    * A **stream handle** (`t:stream/0`) — a single bidirectional QUIC stream used
      for data exchange within that connection.

  For the client path, both handles are established during `connect/4`. For the
  server path, the connection handle is set via `new/2` (typically after accepting
  a raw QUIC connection from a listener), and the stream handle is obtained by
  calling `accept/2`, which waits for the remote peer to open a stream.

  ## Active mode and message handling

  QUIC streams are kept in `active: :once` mode, mirroring the behaviour of the
  TCP and TLS transports. After each `{:quic, data, stream, props}` message is
  processed by `handle_msg/2` the stream is immediately re-armed for the next
  delivery. Callers should therefore drive the transport through `handle_msg/2`
  rather than `recv/3` when operating in message-passing mode.

  ## ALPN

  The default ALPN token is `"h3"` (HTTP/3). This can be overridden via the
  `:alpn` option passed to `connect/4`.

  ## Dependencies

  Requires the `quicer` optional dependency to be present **and started** (i.e.
  the `:quicer` OTP application must be running).
  """

  require Logger

  alias Ankh.Transport

  @typedoc "QUIC connection handle (opaque reference returned by quicer)"
  @type connection :: reference()

  @typedoc "QUIC stream handle (opaque reference returned by quicer)"
  @type stream :: reference()

  @type t :: %__MODULE__{
          connection: connection() | nil,
          stream: stream() | nil
        }

  defstruct connection: nil, stream: nil

  # ---------------------------------------------------------------------------
  # HTTP/3 stream-management helpers
  #
  # These functions are NOT part of the Ankh.Transport protocol.  They are
  # public module-level functions that the Ankh.Protocol.HTTP3 implementation
  # uses to manage the multiple concurrent QUIC streams that HTTP/3 requires,
  # without reaching into the :quicer NIF directly.
  # ---------------------------------------------------------------------------

  @doc """
  Opens a new bidirectional QUIC stream on the connection and returns a
  transport struct with that stream handle set.

  Used by `Ankh.Protocol.HTTP3.request/2` to obtain a fresh stream for each
  HTTP/3 request.  The stream is armed with `active: :once` so the first
  incoming message is delivered automatically.
  """
  @spec open_stream(t()) :: {:ok, t()} | {:error, any()}
  def open_stream(%__MODULE__{connection: conn} = transport) when not is_nil(conn) do
    case :quicer.start_stream(conn, %{active: :once}) do
      {:ok, handle} -> {:ok, %{transport | stream: handle}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Opens a new **unidirectional** QUIC stream on the connection and immediately
  writes `preface` on it.

  Used by the HTTP/3 protocol to set up the control stream immediately after
  a connection is established.  The stream is opened in passive mode (`active:
  false`) because it is write-only from this endpoint's perspective; data
  arriving on peer-initiated unidirectional streams is delivered via the
  `:new_stream` / binary-data QUIC messages instead.
  """
  @spec open_unidirectional_stream(t(), iodata()) :: :ok | {:error, any()}
  def open_unidirectional_stream(%__MODULE__{connection: conn}, preface)
      when not is_nil(conn) do
    # open_flag: 1 is QUIC_STREAM_OPEN_FLAG_UNIDIRECTIONAL
    with {:ok, handle} <- :quicer.start_stream(conn, %{open_flag: 1, active: false}) do
      case :quicer.send(handle, IO.iodata_to_binary(preface)) do
        {:ok, _bytes} -> :ok
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Gracefully shuts down the **send side** of the stored stream (QUIC FIN),
  signalling to the peer that no more data will be sent.

  This does **not** close the connection.  Used after sending the last frame
  on a request or response stream so the peer knows the message is complete.
  """
  @spec shutdown_stream(t()) :: :ok | {:error, any()}
  def shutdown_stream(%__MODULE__{stream: stream}) when not is_nil(stream) do
    :quicer.shutdown_stream(stream, 5_000)
  end

  @doc """
  Re-arms `active: :once` mode on the stored stream after a single QUIC data
  message has been delivered.

  Must be called inside the `stream/2` handler each time a
  `{:quic, data, stream_handle, props}` message is processed, so that the
  next incoming message is delivered to the owning process.
  """
  @spec rearm_stream(t()) :: :ok
  def rearm_stream(%__MODULE__{stream: stream}) when not is_nil(stream) do
    case :quicer.setopt(stream, :active, :once) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("QUIC stream re-arm error: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Closes the QUIC **connection** without first closing a specific stream.

  Used by `Ankh.Protocol.HTTP3.error/1` to tear down the whole connection
  when a connection-level error is detected.
  """
  @spec close_connection(t()) :: :ok | {:error, any()}
  def close_connection(%__MODULE__{connection: conn}) when not is_nil(conn) do
    case :quicer.close_connection(conn) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defimpl Transport do
    # Default ALPN for HTTP/3.
    @default_alpn ["h3"]

    # Stream options used when opening or accepting a stream.
    # `active: :once` delivers exactly one message then disarms, matching
    # the behaviour of the TCP/TLS transports.
    @default_stream_opts [active: :once]

    # ---------------------------------------------------------------------------
    # new/2
    # ---------------------------------------------------------------------------

    @doc """
    Initialises the transport from an existing QUIC handle.

    Accepts either:

      * A bare `connection_handle()` — used on the server path where the
        connection has already been accepted from a listener.  The stream
        field is left `nil` and must be populated via `accept/2` before
        data can flow.

      * A `{connection_handle(), stream_handle()}` tuple — used when both
        handles are already known (e.g. when handing an established session
        off to another process).
    """
    def new(%@for{} = transport, {connection, stream})
        when is_reference(connection) and is_reference(stream) do
      {:ok, %{transport | connection: connection, stream: stream}}
    end

    def new(%@for{} = transport, connection) when is_reference(connection) do
      {:ok, %{transport | connection: connection}}
    end

    # ---------------------------------------------------------------------------
    # connect/4
    # ---------------------------------------------------------------------------

    @doc """
    Opens a QUIC connection to the given `uri`.

    Returns a transport with only the `connection` field set (`stream: nil`).
    Streams are not opened automatically; use `Ankh.Transport.QUIC.open_stream/1`
    or `Ankh.Transport.QUIC.open_unidirectional_stream/2` at the protocol layer
    to create streams on demand.

    Supported options (all optional):

      * `:alpn` — list of ALPN tokens; defaults to `[~c"h3"]`.
        Must be charlists (Erlang strings), not Elixir binaries.
      * `:verify` — peer certificate verification; defaults to `:verify_peer`.
      * `:cacertfile` — path to a CA certificate bundle.
      * `:certfile` — path to a client certificate (mTLS).
      * `:keyfile` — path to the private key for the client certificate.
      * `:password` — passphrase for an encrypted private key.
      * `:peer_unidi_stream_count` — number of unidirectional streams the remote
        peer is allowed to open; useful for HTTP/3 control/QPACK streams.
    """
    def connect(%@for{} = transport, %URI{host: host, port: port}, timeout, options) do
      hostname = String.to_charlist(host)
      alpn = Keyword.get(options, :alpn, @default_alpn)
      verify = Keyword.get(options, :verify, :verify_peer)

      conn_opts =
        [alpn: alpn, verify: verify]
        |> Keyword.merge(
          Keyword.take(options, [
            :cacertfile,
            :certfile,
            :keyfile,
            :password,
            :peer_unidi_stream_count,
            :peer_bidi_stream_count
          ])
        )
        |> Map.new()

      with {:ok, conn} <- :quicer.connect(hostname, port || 443, conn_opts, timeout) do
        {:ok, %{transport | connection: conn}}
      end
    end

    # ---------------------------------------------------------------------------
    # accept/2
    # ---------------------------------------------------------------------------

    @doc """
    Accepts an inbound QUIC stream on an already-established connection.

    The connection handle must have been set beforehand via `new/2`.  This call
    blocks until the remote peer opens a stream or an error occurs.

    Any additional `options` are merged with the default stream options and
    forwarded to `:quicer.accept_stream/2`.
    """
    def accept(%@for{connection: conn} = transport, options) when not is_nil(conn) do
      stream_opts = @default_stream_opts |> Keyword.merge(options) |> Map.new()

      with {:ok, stream} <- :quicer.accept_stream(conn, stream_opts) do
        {:ok, %{transport | stream: stream}}
      end
    end

    def accept(%@for{connection: nil}, _options) do
      {:error, :no_connection}
    end

    # ---------------------------------------------------------------------------
    # send/2
    # ---------------------------------------------------------------------------

    @doc """
    Sends `data` over the QUIC stream synchronously.

    The data is converted to a binary via `IO.iodata_to_binary/1` before being
    handed off to `:quicer.send/2`, which blocks until the send is acknowledged
    by the transport layer.
    """
    def send(%@for{stream: stream}, data) when not is_nil(stream) do
      case :quicer.send(stream, IO.iodata_to_binary(data)) do
        {:ok, _bytes_sent} -> :ok
        {:error, _} = error -> error
      end
    end

    def send(%@for{stream: nil}, _data) do
      {:error, :no_stream}
    end

    # ---------------------------------------------------------------------------
    # recv/3
    # ---------------------------------------------------------------------------

    @doc """
    Passively reads up to `size` bytes from the QUIC stream.

    Pass `size = 0` to retrieve all currently available data in the receive
    buffer (the quicer default behaviour for a zero-length read).

    The `timeout` argument is accepted for interface compatibility but is not
    forwarded to quicer; quicer manages its own internal timeouts.
    """
    def recv(%@for{stream: stream}, size, _timeout) when not is_nil(stream) do
      :quicer.recv(stream, size)
    end

    def recv(%@for{stream: nil}, _size, _timeout) do
      {:error, :no_stream}
    end

    # ---------------------------------------------------------------------------
    # close/1
    # ---------------------------------------------------------------------------

    @doc """
    Gracefully closes the QUIC stream and then the underlying connection.

    The stream is shut down with a FIN (graceful half-close of the send side)
    before the connection is closed.  Errors from individual close calls are
    logged but do not prevent the other handle from being closed.
    """
    def close(%@for{connection: conn, stream: stream} = transport) do
      if not is_nil(stream) do
        case :quicer.close_stream(stream) do
          :ok ->
            :ok

          {:error, reason} = error ->
            Logger.debug("QUIC stream close error: #{inspect(reason)}")
            error
        end
      end

      if not is_nil(conn) do
        case :quicer.close_connection(conn) do
          :ok ->
            :ok

          {:error, reason} = error ->
            Logger.debug("QUIC connection close error: #{inspect(reason)}")
            error
        end
      end

      {:ok, %{transport | connection: nil, stream: nil}}
    end

    # ---------------------------------------------------------------------------
    # handle_msg/2
    # ---------------------------------------------------------------------------

    @doc """
    Handles asynchronous messages delivered by the quicer NIF.

    ## Handled messages

      * `{:quic, data, stream, props}` — binary data arrived on our stream.
        The stream is re-armed for the next `active: :once` delivery before
        returning `{:ok, data}`.
      * `{:quic, :peer_send_shutdown, stream, _}` — the remote peer has
        half-closed its send side (sent a FIN).
      * `{:quic, :peer_send_aborted, stream, _}` — the remote peer aborted
        its send side.
      * `{:quic, :stream_closed, stream, _}` — the stream has been fully
        closed by both sides.
      * `{:quic, :transport_shutdown, conn, _}` — the QUIC connection was
        shut down by the transport (e.g. idle timeout, network loss).
      * `{:quic, :closed, conn, _}` — the QUIC connection was closed.

    All other messages return `{:other, msg}` so the caller can handle them.
    """

    # HTTP/3 passthrough mode: when no specific stream is stored, the QUIC
    # transport is operating as a bare connection handle on behalf of the
    # HTTP/3 protocol layer.  Pass every QUIC message through as-is so that
    # `Ankh.Protocol.HTTP3.stream/2` can inspect the stream handle and
    # dispatch to the correct per-request stream state machine.
    def handle_msg(%@for{stream: nil}, {:quic, _, _, _} = msg), do: {:ok, msg}

    # Binary data on our stream — re-arm active mode and return the payload.
    def handle_msg(%@for{stream: stream}, {:quic, data, stream, _props})
        when is_binary(data) and not is_nil(stream) do
      case :quicer.setopt(stream, :active, :once) do
        :ok ->
          {:ok, data}

        {:error, reason} ->
          Logger.debug("QUIC stream re-arm error: #{inspect(reason)}")
          {:ok, data}
      end
    end

    # Remote peer finished sending (graceful FIN).
    def handle_msg(%@for{stream: stream}, {:quic, :peer_send_shutdown, stream, _props})
        when not is_nil(stream) do
      {:error, :closed}
    end

    # Remote peer aborted its send side.
    def handle_msg(%@for{stream: stream}, {:quic, :peer_send_aborted, stream, _error_code})
        when not is_nil(stream) do
      {:error, :closed}
    end

    # Stream has been fully closed.
    def handle_msg(%@for{stream: stream}, {:quic, :stream_closed, stream, _props})
        when not is_nil(stream) do
      {:error, :closed}
    end

    # Transport-level shutdown (e.g. idle timeout, network error).
    def handle_msg(%@for{connection: conn}, {:quic, :transport_shutdown, conn, props})
        when not is_nil(conn) do
      Logger.debug("QUIC transport shutdown: #{inspect(props)}")
      {:error, :closed}
    end

    # Connection closed.
    def handle_msg(%@for{connection: conn}, {:quic, :closed, conn, _props})
        when not is_nil(conn) do
      {:error, :closed}
    end

    # Unrelated message — pass it through for the caller to handle.
    def handle_msg(_quic, msg), do: {:other, msg}

    # ---------------------------------------------------------------------------
    # negotiated_protocol/1
    # ---------------------------------------------------------------------------

    @doc """
    Returns the ALPN protocol negotiated during the QUIC handshake.

    Delegates to `:quicer.negotiated_protocol/1` on the connection handle.
    Returns `{:error, :protocol_not_negotiated}` if no connection is present.
    """
    # quicer's negotiated_protocol/1 delegates to quicer_nif:getopt/3, a NIF
    # whose Dialyzer success-typing resolves to only {:error, atom()}.  The
    # quicer @spec correctly declares {:ok, binary()} | {:error, any()}, but
    # Dialyzer's conservative NIF analysis cannot see the {:ok, _} branch as
    # reachable.  This is a confirmed false positive; suppress it here rather
    # than in the ignore-warnings file because Erlex fails to parse the raw
    # Erlang type in the warning args, causing dialyxir's filter to silently
    # skip the entry.
    @dialyzer {:nowarn_function, [negotiated_protocol: 1]}
    def negotiated_protocol(%@for{connection: conn}) when not is_nil(conn) do
      case :quicer.negotiated_protocol(conn) do
        {:ok, protocol} ->
          {:ok, protocol}

        {:error, _reason} ->
          {:error, :protocol_not_negotiated}
      end
    end

    def negotiated_protocol(%@for{connection: nil}) do
      {:error, :protocol_not_negotiated}
    end
  end
end
