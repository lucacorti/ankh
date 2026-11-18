defmodule Ankh.Transport.QUIC do
  @moduledoc """
  QUIC transport implementation using the `erlang_quic` library.

  This transport uses `erlang_quic` (https://github.com/benoitc/erlang_quic), a
  pure-Erlang QUIC implementation (RFC 9000 / 9001).

  ## Differences from TCP/TLS

  Unlike TCP or TLS transports, which expose a single bytestream socket, QUIC is
  inherently multiplexed. The QUIC transport therefore manages two distinct handles:

    * A **connection handle** (`t:connection/0`) — the underlying QUIC connection
      (a `pid()`).
    * A **stream handle** (`t:stream/0`) — a non-negative integer identifying one
      bidirectional QUIC stream used for data exchange within that connection.

  For the client path, both handles are established during `connect/4`. For the
  server path, the connection handle is set via `new/2` (typically after accepting
  a raw QUIC connection from a listener), and the stream handle is obtained by
  calling `accept/2`, which waits for the remote peer to open a stream.

  ## Message delivery

  `erlang_quic` delivers all QUIC events as messages to the owning process
  automatically — there is no `active: :once` mode to re-arm. After each message
  the process can simply call `handle_msg/2` to decode it.

  ## ALPN

  The default ALPN token is `"h3"` (HTTP/3) as a binary string.

  ## Dependencies

  Requires the `quic` optional dependency (erlang_quic) to be present and started.
  """

  alias Ankh.Transport

  @typedoc "QUIC connection handle (pid returned by erlang_quic)"
  @type connection :: pid()

  @typedoc "QUIC stream identifier (non-negative integer returned by erlang_quic)"
  @type stream :: non_neg_integer()

  @type t :: %__MODULE__{
          connection: connection() | nil,
          stream: stream() | nil,
          alpn: String.t() | nil
        }

  defstruct connection: nil, stream: nil, alpn: nil

  @doc """
  Opens a new bidirectional QUIC stream on the connection and returns a
  transport struct with that stream handle set.

  Used by `Ankh.Protocol.HTTP3.request/2` to obtain a fresh stream for each
  HTTP/3 request.
  """
  @spec open_stream(t()) :: {:ok, t()} | {:error, any()}
  def open_stream(%__MODULE__{connection: conn} = transport) when not is_nil(conn) do
    case :quic.open_stream(conn) do
      {:ok, stream_id} -> {:ok, %{transport | stream: stream_id}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Opens a new **unidirectional** QUIC stream on the connection and immediately
  writes `preface` on it.

  Used by the HTTP/3 protocol to set up the control stream immediately after
  a connection is established.
  """
  @spec open_unidirectional_stream(t(), iodata()) :: :ok | {:error, any()}
  def open_unidirectional_stream(%__MODULE__{connection: conn}, preface)
      when not is_nil(conn) do
    with {:ok, stream_id} <- :quic.open_unidirectional_stream(conn) do
      :quic.send_data(conn, stream_id, preface, false)
    end
  end

  @doc """
  Gracefully shuts down the **send side** of the stored stream (QUIC FIN),
  signalling to the peer that no more data will be sent.

  This does **not** close the connection.
  """
  @spec shutdown_stream(t()) :: :ok | {:error, any()}
  def shutdown_stream(%__MODULE__{connection: conn, stream: stream})
      when not is_nil(conn) and not is_nil(stream) do
    :quic.send_data(conn, stream, <<>>, true)
  end

  defimpl Transport do
    @doc """
    Initialises the transport from an existing QUIC handle.

    Accepts either:

      * A bare `connection()` (pid) — used on the server path where the
        connection has already been accepted from a listener. The stream field is
        left `nil` and must be populated via `accept/2` before data can flow.

      * A `{connection(), stream()}` tuple — used when both handles are already
        known.
    """
    def new(%@for{} = transport, {connection, stream})
        when is_pid(connection) and is_integer(stream),
        do: {:ok, %{transport | connection: connection, stream: stream}}

    def new(%@for{} = transport, connection) when is_pid(connection),
      do: {:ok, %{transport | connection: connection}}

    @doc """
    Opens a QUIC connection to the given `uri`.

    `erlang_quic`'s connect is asynchronous: `:quic.connect/4` returns
    `{:ok, conn_pid}` immediately and the calling process then receives
    `{:quic, conn_pid, {:connected, info}}` when the TLS handshake completes.
    This function blocks internally (using `receive … after timeout`) to present
    a synchronous interface to the caller.

    Returns a transport with only the `connection` field set (`stream: nil`).
    Streams are not opened automatically; use `Ankh.Transport.QUIC.open_stream/1`
    or `Ankh.Transport.QUIC.open_unidirectional_stream/2` at the protocol layer
    to create streams on demand.

    Supported options (all optional):

      * `:alpn` — list of ALPN tokens as binaries; defaults to `["h3"]`.
      * `:verify` — peer certificate verification; pass `true` or `:verify_peer`
        to verify. Defaults to `false`.
      * `:cacertfile` — path to a CA certificate bundle.
      * `:certfile` — path to a client certificate (mTLS).
      * `:keyfile` — path to the private key for the client certificate.
      * `:password` — passphrase for an encrypted private key.
    """
    def connect(%@for{} = transport, %URI{host: host, port: port}, timeout, options) do
      alpn = Keyword.get(options, :alpn, ["h3"])

      verify =
        case Keyword.get(options, :verify, false) do
          :verify_peer -> true
          :verify_none -> false
          verify when is_boolean(verify) -> verify
          _verify -> false
        end

      conn_opts =
        %{alpn: alpn, verify: verify}
        |> maybe_put(:cacertfile, Keyword.get(options, :cacertfile))
        |> maybe_put(:certfile, Keyword.get(options, :certfile))
        |> maybe_put(:keyfile, Keyword.get(options, :keyfile))
        |> maybe_put(:password, Keyword.get(options, :password))

      case :quic.connect(host, port || 443, conn_opts, self()) do
        {:ok, conn_pid} ->
          receive do
            {:quic, ^conn_pid, {:connected, _info}} ->
              negotiated = List.first(alpn, "h3")
              {:ok, %{transport | connection: conn_pid, alpn: negotiated}}

            {:quic, ^conn_pid, {:closed, reason}} ->
              {:error, reason}

            {:quic, ^conn_pid, {:transport_error, _code, reason}} ->
              {:error, reason}
          after
            timeout ->
              {:error, :timeout}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)

    @doc """
    Accepts an inbound QUIC stream on an already-established connection.

    The connection handle must have been set beforehand via `new/2`.  This call
    blocks until the remote peer opens a stream (delivering
    `{:quic, conn, {:stream_opened, stream_id}}`) or until the 5-second timeout
    expires.

    Note: in HTTP/3 mode streams arrive as asynchronous messages handled by
    `Ankh.Protocol.HTTP3.stream/2`, so this function is primarily used for
    single-stream protocols (HTTP/1.1, HTTP/2) over QUIC.
    """
    def accept(%@for{connection: conn} = transport, _options) when not is_nil(conn) do
      receive do
        {:quic, ^conn, {:stream_opened, stream_id}} ->
          {:ok, %{transport | stream: stream_id}}
      after
        5_000 ->
          {:error, :timeout}
      end
    end

    def accept(%@for{connection: nil}, _options), do: {:error, :no_connection}

    @doc """
    Sends `data` over the QUIC stream synchronously.

    Calls `:quic.send_data/4` with `fin = false`.
    """
    def send(%@for{connection: conn, stream: stream}, data)
        when not is_nil(conn) and not is_nil(stream),
        do: :quic.send_data(conn, stream, data, false)

    def send(%@for{stream: nil}, _data), do: {:error, :no_stream}

    @doc """
    Passively reads data from the QUIC stream by blocking on the next
    `{:quic, conn, {:stream_data, stream_id, data, _fin}}` message.

    The `size` argument is accepted for interface compatibility but is not
    enforced — `erlang_quic` does not support partial reads.
    """
    def recv(%@for{connection: conn, stream: stream}, _size, timeout)
        when not is_nil(conn) and not is_nil(stream) do
      receive do
        {:quic, ^conn, {:stream_data, ^stream, data, _fin}} ->
          {:ok, data}
      after
        timeout ->
          {:error, :timeout}
      end
    end

    def recv(%@for{stream: nil}, _size, _timeout), do: {:error, :no_stream}

    @doc """
    Closes the underlying QUIC connection.

    Unlike the quicer-based implementation there is no separate stream-close
    call; `:quic.close/1` tears down the whole connection.
    """
    def close(%@for{connection: conn} = transport) do
      if not is_nil(conn), do: :quic.close(conn)
      {:ok, %{transport | connection: nil, stream: nil}}
    end

    @doc """
    Handles asynchronous messages delivered by `erlang_quic`.

    ## Handled messages

      * `{:quic, conn, {:stream_data, stream_id, data, false}}` — binary data
        arrived on our stream. Returns `{:ok, data}`.
      * `{:quic, conn, {:stream_data, stream_id, data, true}}` — final data
        chunk with FIN. Returns `{:ok, data}` if non-empty, `{:error, :closed}`
        otherwise.
      * `{:quic, conn, {:stream_reset, stream_id, _}}` — stream reset by peer.
      * `{:quic, conn, {:closed, _}}` — connection closed.
      * `{:quic, conn, {:transport_error, _, _}}` — transport-level error.

    All other messages return `{:other, msg}` so the caller can handle them.
    """

    # HTTP/3 passthrough mode: when no specific stream is stored, the QUIC
    # transport is operating as a bare connection handle on behalf of the
    # HTTP/3 protocol layer. Pass every QUIC message through as-is so that
    # `Ankh.Protocol.HTTP3.stream/2` can dispatch to the correct per-request
    # stream state machine.
    def handle_msg(%@for{stream: nil}, {:quic, _, _} = msg), do: {:ok, msg}

    # Binary data on our stream, no FIN.
    def handle_msg(
          %@for{connection: conn, stream: stream},
          {:quic, conn, {:stream_data, stream, data, false}}
        )
        when is_binary(data) and not is_nil(stream), do: {:ok, data}

    # Final data chunk with FIN.
    def handle_msg(
          %@for{connection: conn, stream: stream},
          {:quic, conn, {:stream_data, stream, data, true}}
        )
        when is_binary(data) and not is_nil(stream) do
      if data != <<>>, do: {:ok, data}, else: {:error, :closed}
    end

    # Stream reset by peer.
    def handle_msg(
          %@for{connection: conn, stream: stream},
          {:quic, conn, {:stream_reset, stream, _error_code}}
        )
        when not is_nil(stream), do: {:error, :closed}

    # Connection closed.
    def handle_msg(%@for{connection: conn}, {:quic, conn, {:closed, _reason}})
        when not is_nil(conn), do: {:error, :closed}

    # Transport error.
    def handle_msg(%@for{connection: conn}, {:quic, conn, {:transport_error, _code, _reason}})
        when not is_nil(conn), do: {:error, :closed}

    # Unrelated message — pass it through for the caller to handle.
    def handle_msg(_quic, msg), do: {:other, msg}

    @doc """
    Returns the ALPN protocol stored during `connect/4`, or `"h3"` if this
    transport was initialised on the server side without going through `connect/4`.

    `erlang_quic` does not expose a `negotiated_protocol/1` query function;
    the negotiated ALPN is inferred from the first token in the requested list
    (connection succeeds only if the server agrees).
    """
    def negotiated_protocol(%@for{alpn: alpn}) when not is_nil(alpn), do: {:ok, alpn}
    def negotiated_protocol(%@for{connection: conn}) when not is_nil(conn), do: {:ok, "h3"}
    def negotiated_protocol(%@for{connection: nil}), do: {:error, :protocol_not_negotiated}
  end
end
