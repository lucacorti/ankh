defmodule Ankh.Protocol.HTTP3 do
  @moduledoc """
  HTTP/3 protocol implementation for Ankh.

  This module implements the `Ankh.Protocol` protocol over a QUIC connection
  managed by the `quicer` library. It supports both the client (`connect/4`) and
  server (`accept/5`) sides of an HTTP/3 connection.

  ## Architecture

  Unlike TCP-based HTTP protocols, QUIC is inherently multiplexed. Each logical
  HTTP request/response pair runs on its own QUIC stream. When operating in HTTP/3
  mode the `Ankh.Transport.QUIC` struct has `stream: nil`; raw QUIC messages are
  forwarded directly to this protocol's `stream/2` callback rather than being
  unwrapped by the transport layer.

  Each QUIC stream is tracked in the `streams` map keyed by the opaque quicer
  stream handle. A parallel `references` map provides the reverse lookup from
  Elixir request references to stream handles, allowing callers to correlate
  `stream/2` response events back to the originating `request/2` or `respond/3`
  call.

  ## Header compression

  All header compression and decompression is delegated to
  `Ankh.Protocol.HTTP3.QPACK`. Both the send and receive QPACK contexts are
  initialised in static-only mode (`max_table_capacity = 0`), which eliminates
  the need for dedicated QPACK encoder and decoder streams and is declared in
  the SETTINGS preface written on the control stream.

  ## HTTP/3 framing

  Frame encoding and decoding (HEADERS, DATA, SETTINGS, GOAWAY, etc.) are
  delegated to `Ankh.Protocol.HTTP3.Frame`. Variable-length integer encoding
  follows RFC 9000 §16.

  ## Control stream

  Both `accept/5` and `connect/4` open a unidirectional HTTP/3 control stream
  immediately after establishing the connection and write the mandatory SETTINGS
  preface before returning. This satisfies the RFC 9114 §6.2.1 requirement that
  a SETTINGS frame MUST be the first frame sent on the control stream.

  ## Per-stream lifecycle

  Each QUIC stream's HTTP/3 state is tracked by an `Ankh.Protocol.HTTP3.Stream`
  struct that models the stream lifecycle
  (`idle → open → half_closed_local/remote → closed`) and accumulates incoming
  bytes between message deliveries. Frame parsing runs over the accumulated buffer
  and any unconsumed remainder is retained for the next delivery.

  ## Incoming message dispatch

  `stream/2` pattern-matches the raw QUIC tuple messages delivered by quicer:

    * `{:quic, data, handle, _}` — binary data; appended to the stream buffer
      and parsed as HTTP/3 frames.
    * `{:quic, :peer_send_shutdown, handle, _}` — remote FIN; signals
      end-of-stream to the caller via an empty DATA event with `complete = true`.
    * `{:quic, :stream_closed, handle, _}` — stream fully closed by both sides.
    * `{:quic, :new_stream, handle, props}` — new inbound stream from the peer
      (server-side).
    * `{:quic, :transport_shutdown | :closed, _, _}` — connection teardown;
      returns `{:error, :closed}`.

  ## References

    * RFC 9114 — HTTP/3
    * RFC 9000 — QUIC Transport Protocol
    * RFC 9204 — QPACK: Field Compression for HTTP/3
  """

  alias Ankh.{Protocol, Transport}
  alias Ankh.Protocol.HTTP3.{QPACK, Stream}
  alias Ankh.Transport.QUIC

  @typedoc """
  Opaque HTTP/3 protocol state struct.

  Carries the QPACK encode/decode contexts, the per-stream state maps, the
  underlying QUIC transport, the connection URI, and both local and remote
  SETTINGS values.
  """
  @opaque t :: %__MODULE__{
            mode: :client | :server | nil,
            recv_qpack: QPACK.t() | nil,
            send_qpack: QPACK.t() | nil,
            streams: %{optional(reference()) => Stream.t()},
            references: %{optional(reference()) => reference()},
            transport: QUIC.t() | nil,
            uri: URI.t() | nil,
            local_settings: keyword(),
            remote_settings: keyword()
          }

  defstruct mode: nil,
            recv_qpack: nil,
            send_qpack: nil,
            streams: %{},
            references: %{},
            transport: nil,
            uri: nil,
            local_settings: [],
            remote_settings: []

  defimpl Protocol do
    alias Ankh.HTTP.{Request, Response}
    alias Ankh.Protocol.HTTP3.{Frame, QPACK, Stream}

    alias Ankh.Protocol.HTTP3.Frame.{
      CancelPush,
      Data,
      GoAway,
      Headers,
      MaxPushId,
      PushPromise,
      Settings
    }

    alias Ankh.Transport
    alias Ankh.Transport.QUIC
    require Logger

    # -------------------------------------------------------------------------
    # accept/5 — server side
    # -------------------------------------------------------------------------

    @doc """
    Accepts an incoming QUIC connection and initialises the HTTP/3 server state.

    Initialises QPACK encode/decode contexts in static-only mode, opens a
    unidirectional HTTP/3 control stream on the accepted connection, and writes
    the mandatory SETTINGS preface (RFC 9114 §6.2.1) before returning.

    The `socket` argument must be a raw QUIC connection handle (`reference()`)
    as returned by quicer after accepting a connection from a listener.
    """
    def accept(%@for{} = protocol, uri, transport, socket, _options) do
      with {:ok, %QUIC{connection: conn} = transport} <- Transport.new(transport, socket),
           :ok <- QUIC.open_unidirectional_stream(transport, Frame.control_stream_preface()) do
        Logger.debug("HTTP/3 server accepted connection: #{inspect(conn)}")

        {:ok,
         %@for{
           protocol
           | mode: :server,
             transport: transport,
             uri: uri,
             recv_qpack: QPACK.new(),
             send_qpack: QPACK.new()
         }}
      end
    end

    # -------------------------------------------------------------------------
    # connect/4 — client side
    # -------------------------------------------------------------------------

    @doc """
    Initialises the HTTP/3 client state on an already-established QUIC connection.

    The QUIC connection handle must already be present in `transport.connection`
    (established by the caller, e.g. via `Ankh.HTTP.connect/2`). Initialises
    QPACK contexts, opens a unidirectional control stream, and sends the SETTINGS
    preface before returning.
    """
    def connect(%@for{} = protocol, uri, %QUIC{connection: conn} = transport, _options) do
      with :ok <- QUIC.open_unidirectional_stream(transport, Frame.control_stream_preface()) do
        Logger.debug("HTTP/3 client connected: #{inspect(conn)}")

        {:ok,
         %@for{
           protocol
           | mode: :client,
             transport: transport,
             uri: uri,
             recv_qpack: QPACK.new(),
             send_qpack: QPACK.new()
         }}
      end
    end

    # -------------------------------------------------------------------------
    # error/1
    # -------------------------------------------------------------------------

    @doc """
    Closes the QUIC connection, signalling a connection-level error to the peer.
    """
    def error(%@for{transport: transport}), do: Transport.close(transport)

    # -------------------------------------------------------------------------
    # request/2
    # -------------------------------------------------------------------------

    @doc """
    Sends an HTTP/3 request on a new bidirectional QUIC stream.

    Constructs the complete header block — pseudo-headers (`:method`, `:scheme`,
    `:authority`, `:path`) in order, followed by the request's regular headers —
    QPACK-encodes it, and sends it in an HTTP/3 HEADERS frame on a freshly opened
    bidirectional stream. If the request body is non-empty, a DATA frame follows
    and the stream is gracefully shut down (FIN).

    Returns `{:ok, updated_protocol, ref}` where `ref` is the Elixir
    `reference()` that identifies this request in subsequent `stream/2` events.
    """
    def request(
          %@for{
            uri: %{authority: authority, scheme: scheme},
            transport: transport
          } = protocol,
          %Request{method: method, path: path, headers: req_headers, body: body}
        ) do
      pseudo_headers = [
        {":method", Atom.to_string(method)},
        {":scheme", to_string(scheme)},
        {":authority", to_string(authority)},
        {":path", path || "/"}
      ]

      all_headers = pseudo_headers ++ req_headers
      {hbf, send_qpack} = QPACK.encode(:store, all_headers, protocol.send_qpack)

      headers_bin = IO.iodata_to_binary(hbf)

      {:ok, _, headers_frame_data} =
        Frame.encode(%Headers{payload: %Headers.Payload{hbf: headers_bin}})

      headers_frame_bin = IO.iodata_to_binary(headers_frame_data)

      with {:ok, stream_transport} <- QUIC.open_stream(transport),
           :ok <- Transport.send(stream_transport, headers_frame_bin) do
        if IO.iodata_length(body) > 0 do
          body_bin = IO.iodata_to_binary(body)

          {:ok, _, data_frame_data} =
            Frame.encode(%Data{payload: %Data.Payload{data: body_bin}})

          data_frame_bin = IO.iodata_to_binary(data_frame_data)
          Transport.send(stream_transport, data_frame_bin)
        end

        # Always FIN the send side — even for no-body requests (e.g. GET).
        # Without this the server never knows the request is complete and
        # will not send a response.
        QUIC.shutdown_stream(stream_transport)

        handle = stream_transport.stream
        stream = Stream.new_request(handle)
        ref = stream.reference

        Logger.debug("HTTP/3 request sent: #{method} #{path} ref=#{inspect(ref)}")

        protocol = %@for{
          protocol
          | send_qpack: send_qpack,
            streams: Map.put(protocol.streams, handle, stream),
            references: Map.put(protocol.references, ref, handle)
        }

        {:ok, protocol, ref}
      end
    end

    # -------------------------------------------------------------------------
    # respond/3
    # -------------------------------------------------------------------------

    @doc """
    Sends an HTTP/3 response on the stream identified by `request_reference`.

    Builds the `:status` pseudo-header, appends the response headers, QPACK-
    encodes the full block, and sends it in a HEADERS frame. If the response body
    is non-empty a DATA frame follows. If trailers are present they are
    QPACK-encoded and sent as a second HEADERS frame. Finally, the stream is
    gracefully shut down (FIN).
    """
    def respond(
          %@for{} = protocol,
          request_reference,
          %Response{status: status, headers: resp_headers, body: body, trailers: trailers}
        ) do
      with {:ok, handle, stream} <- lookup_stream(protocol, request_reference) do
        pseudo_headers = [{":status", Integer.to_string(status)}]
        all_headers = pseudo_headers ++ resp_headers

        {hbf, send_qpack} = QPACK.encode(:store, all_headers, protocol.send_qpack)

        headers_bin = IO.iodata_to_binary(hbf)

        {:ok, _, headers_frame_data} =
          Frame.encode(%Headers{payload: %Headers.Payload{hbf: headers_bin}})

        headers_frame_bin = IO.iodata_to_binary(headers_frame_data)
        %QUIC{} = quic_transport = protocol.transport
        stream_transport = %QUIC{quic_transport | stream: handle}
        Transport.send(stream_transport, headers_frame_bin)

        if IO.iodata_length(body) > 0 do
          body_bin = IO.iodata_to_binary(body)

          {:ok, _, data_frame_data} =
            Frame.encode(%Data{payload: %Data.Payload{data: body_bin}})

          data_frame_bin = IO.iodata_to_binary(data_frame_data)
          Transport.send(stream_transport, data_frame_bin)
        end

        send_qpack =
          if trailers != [] do
            {trailer_hbf, sq} = QPACK.encode(:store, trailers, send_qpack)
            trailer_bin = IO.iodata_to_binary(trailer_hbf)

            {:ok, _, trailer_frame_data} =
              Frame.encode(%Headers{payload: %Headers.Payload{hbf: trailer_bin}})

            trailer_frame_bin = IO.iodata_to_binary(trailer_frame_data)
            Transport.send(stream_transport, trailer_frame_bin)
            sq
          else
            send_qpack
          end

        QUIC.shutdown_stream(stream_transport)

        stream = Stream.local_fin(stream)

        Logger.debug("HTTP/3 response sent: #{status} ref=#{inspect(request_reference)}")

        protocol = %@for{
          protocol
          | send_qpack: send_qpack,
            streams: Map.put(protocol.streams, handle, stream)
        }

        {:ok, protocol}
      end
    end

    # -------------------------------------------------------------------------
    # stream/2 — incoming QUIC message dispatcher
    # -------------------------------------------------------------------------

    @doc """
    Dispatches a raw QUIC message and returns HTTP/3 response events.

    This is the sole entry point for all incoming data and connection-level
    events in HTTP/3 mode.  Each clause delegates to a private helper that
    returns `{:ok, protocol, responses}` or `{:error, reason}`.

    Response tuples follow the `Ankh.HTTP.response()` shape:

      * `{:headers, ref, headers, complete?}` — a decoded HEADERS frame
      * `{:data, ref, data, complete?}` — a DATA frame or end-of-stream signal
      * `{:error, ref, reason, true}` — a stream-level protocol error
    """
    def stream(%@for{} = protocol, {:quic, data, stream_handle, _props})
        when is_binary(data) do
      handle_stream_data(protocol, stream_handle, data)
    end

    def stream(%@for{} = protocol, {:quic, :peer_send_shutdown, stream_handle, _props}) do
      handle_peer_send_shutdown(protocol, stream_handle)
    end

    def stream(%@for{} = protocol, {:quic, :stream_closed, stream_handle, _props}) do
      handle_stream_closed(protocol, stream_handle)
    end

    def stream(%@for{} = protocol, {:quic, :new_stream, stream_handle, props}) do
      handle_new_stream(protocol, stream_handle, props)
    end

    def stream(%@for{} = _protocol, {:quic, :transport_shutdown, _conn, _props}) do
      {:error, :closed}
    end

    def stream(%@for{} = _protocol, {:quic, :closed, _conn, _props}) do
      {:error, :closed}
    end

    def stream(%@for{} = protocol, _msg) do
      {:ok, protocol, []}
    end

    # =========================================================================
    # Private helpers
    # =========================================================================

    # Resolves an Elixir request reference to its quicer stream handle and
    # per-stream state struct.  Returns `{:error, :unknown_reference}` when
    # the reference is not present in the protocol maps.
    defp lookup_stream(%@for{references: references, streams: streams}, ref) do
      with {:ok, handle} <- Map.fetch(references, ref),
           {:ok, stream} <- Map.fetch(streams, handle) do
        {:ok, handle, stream}
      else
        :error -> {:error, :unknown_reference}
      end
    end

    # Handles incoming binary data on a QUIC stream.
    #
    # Retrieves (or lazily creates) the per-stream state, optionally strips the
    # unidirectional stream-type byte (RFC 9114 §6.2 / RFC 9204 §4.2) from
    # newly-seen streams, appends the data to the stream buffer, runs the HTTP/3
    # frame parser, and re-arms active delivery.
    defp handle_stream_data(%@for{streams: streams} = protocol, stream_handle, data) do
      stream = Map.get(streams, stream_handle, Stream.new_incoming(stream_handle, false))

      # For unidirectional streams whose kind has not yet been identified,
      # the very first byte of data is the stream-type byte.  Strip it, resolve
      # the kind, then treat the remainder as HTTP/3 frame data.
      {stream, effective_data} = maybe_identify_stream_kind(stream, data)

      stream = Stream.append(stream, effective_data)

      with {:ok, protocol, responses} <- process_stream_frames(protocol, stream_handle, stream) do
        %QUIC{} = quic_transport = protocol.transport
        QUIC.rearm_stream(%QUIC{quic_transport | stream: stream_handle})
        {:ok, protocol, responses}
      end
    end

    # Strips the stream-type byte from an unidirectional stream whose kind is not
    # yet known and updates the stream kind via `Stream.identify_kind/2`.
    # All other stream kinds pass data through unchanged.
    defp maybe_identify_stream_kind(
           %Stream{kind: :unknown_unidirectional} = stream,
           <<type_byte, rest::binary>>
         ) do
      {Stream.identify_kind(stream, type_byte), rest}
    end

    defp maybe_identify_stream_kind(stream, data), do: {stream, data}

    # Parses all complete HTTP/3 frames from the stream's accumulated buffer and
    # converts them into Ankh response tuples.  Any incomplete trailing bytes are
    # kept in the stream buffer for the next delivery.
    # Maps a wire frame-type integer to the corresponding empty frame struct,
    # mirroring `frame_for_type/1` in `Ankh.Protocol.HTTP2`.  Unknown type
    # integers return `{:error, :not_found}`; the caller ignores them per
    # RFC 9114 §9.
    defp frame_for_type(0x0), do: {:ok, %Data{}}
    defp frame_for_type(0x1), do: {:ok, %Headers{}}
    defp frame_for_type(0x3), do: {:ok, %CancelPush{}}
    defp frame_for_type(0x4), do: {:ok, %Settings{}}
    defp frame_for_type(0x5), do: {:ok, %PushPromise{}}
    defp frame_for_type(0x7), do: {:ok, %GoAway{}}
    defp frame_for_type(0xD), do: {:ok, %MaxPushId{}}
    defp frame_for_type(_), do: {:error, :not_found}

    # Parses all complete HTTP/3 frames from the stream's accumulated buffer,
    # decodes each one into a typed struct via `Frame.decode/2`, and dispatches
    # to `recv_frame/4`.  Mirrors `process_buffer/1` in `Ankh.Protocol.HTTP2`.
    defp process_stream_frames(
           %@for{} = protocol,
           stream_handle,
           %Stream{buffer: buffer} = stream
         ) do
      result =
        buffer
        |> Frame.stream()
        |> Enum.reduce_while(
          {:ok, protocol, stream, []},
          fn
            {rest, nil}, {:ok, p, s, responses} ->
              # Partial frame — store remainder and stop.
              {:halt, {:ok, p, Stream.consume_buffer(s, rest), responses}}

            {rest, {type, payload}}, {:ok, p, s, responses} ->
              s = Stream.consume_buffer(s, rest)

              with {:ok, frame_struct} <- frame_for_type(type),
                   {:ok, frame} <- Frame.decode(frame_struct, payload),
                   {:ok, p, s, new_responses} <- recv_frame(p, s, stream_handle, frame) do
                {:cont, {:ok, p, s, new_responses ++ responses}}
              else
                {:error, :not_found} ->
                  # Unknown frame type — RFC 9114 §9: MUST be ignored.
                  {:cont, {:ok, p, s, responses}}

                {:error, reason} ->
                  {:halt, {:error, reason}}
              end
          end
        )

      case result do
        {:ok, %@for{} = p, s, responses} ->
          p = %@for{p | streams: Map.put(p.streams, stream_handle, s)}
          {:ok, p, Enum.reverse(responses)}

        {:error, _} = error ->
          error
      end
    end

    # HEADERS frame — QPACK-decode the HBF, validate pseudo-headers, emit
    # a `:headers` response event.
    defp recv_frame(
           %@for{recv_qpack: recv_qpack} = protocol,
           stream,
           _stream_handle,
           %Headers{payload: %Headers.Payload{hbf: hbf}}
         ) do
      case QPACK.decode(hbf, recv_qpack) do
        {:ok, headers, recv_qpack} ->
          protocol = %@for{protocol | recv_qpack: recv_qpack}

          case validate_incoming_headers(protocol, stream, headers) do
            :ok ->
              stream = %{stream | recv_headers: true}
              {:ok, protocol, stream, [{:headers, stream.reference, headers, false}]}

            {:error, reason} ->
              {:ok, protocol, stream, [{:error, stream.reference, reason, true}]}
          end

        {:error, reason} ->
          {:ok, protocol, stream, [{:error, stream.reference, reason, true}]}
      end
    end

    # DATA frame — emit a `:data` response event with the raw body bytes.
    defp recv_frame(
           %@for{} = protocol,
           stream,
           _stream_handle,
           %Data{payload: %Data.Payload{data: data}}
         ) do
      {:ok, protocol, stream, [{:data, stream.reference, data, false}]}
    end

    # SETTINGS frame — update `remote_settings` and log; no response event.
    defp recv_frame(
           %@for{} = protocol,
           stream,
           _stream_handle,
           %Settings{payload: %Settings.Payload{settings: settings}}
         ) do
      Logger.debug("HTTP/3 SETTINGS received: #{inspect(settings)}")
      {:ok, %@for{protocol | remote_settings: settings}, stream, []}
    end

    # GOAWAY frame — emit a connection-level error event (RFC 9114 §7.2.6).
    defp recv_frame(%@for{} = protocol, stream, _stream_handle, %GoAway{}) do
      {:ok, protocol, stream, [{:error, stream.reference, :goaway, true}]}
    end

    # All other known and unknown frame types are silently ignored per
    # RFC 9114 §9 ("extension frames MUST be ignored").
    defp recv_frame(%@for{} = protocol, stream, _stream_handle, _frame) do
      {:ok, protocol, stream, []}
    end

    # Validates pseudo-headers on the first HEADERS block of a stream.
    #
    # On a server-mode connection the first block carries request pseudo-headers
    # (`:method`, `:scheme`, `:authority`, `:path`).  On a client-mode connection
    # the first block carries response pseudo-headers (`:status`).  Subsequent
    # HEADERS blocks on the same stream are trailers and skip pseudo-header
    # validation.
    defp validate_incoming_headers(
           %@for{mode: :server},
           %Stream{recv_headers: false},
           headers
         ) do
      Request.validate_headers(headers, false)
    end

    defp validate_incoming_headers(
           %@for{mode: :client},
           %Stream{recv_headers: false},
           headers
         ) do
      Response.validate_headers(headers, false)
    end

    defp validate_incoming_headers(_protocol, _stream, _headers), do: :ok

    # Handles a `:peer_send_shutdown` (remote FIN) event.
    #
    # Transitions the stream to `:half_closed_remote` (or `:closed` if the local
    # side has already sent a FIN) and emits an empty DATA event with
    # `complete = true` to signal end-of-stream to the caller.
    defp handle_peer_send_shutdown(%@for{streams: streams} = protocol, stream_handle) do
      case Map.get(streams, stream_handle) do
        nil ->
          {:ok, protocol, []}

        stream ->
          stream = Stream.remote_fin(stream)
          protocol = %@for{protocol | streams: Map.put(streams, stream_handle, stream)}
          {:ok, protocol, [{:data, stream.reference, <<>>, true}]}
      end
    end

    # Handles a `:stream_closed` event: both transport sides are finished.
    # Applies `remote_fin` and `local_fin` to drive the stream to `:closed`.
    defp handle_stream_closed(%@for{streams: streams} = protocol, stream_handle) do
      case Map.get(streams, stream_handle) do
        nil ->
          {:ok, protocol, []}

        stream ->
          stream =
            stream
            |> Stream.remote_fin()
            |> Stream.local_fin()

          protocol = %@for{protocol | streams: Map.put(streams, stream_handle, stream)}
          {:ok, protocol, []}
      end
    end

    # Handles a `:new_stream` notification from quicer (server-side).
    #
    # Creates the per-stream state (bidirectional for request streams,
    # unidirectional for control/QPACK/push streams), arms active delivery
    # for the new stream, and returns with no immediate response events.
    defp handle_new_stream(%@for{streams: streams} = protocol, stream_handle, props) do
      unidirectional? = Map.get(props, :flags, 0) == 1
      stream = Stream.new_incoming(stream_handle, unidirectional?)

      %QUIC{} = quic_transport = protocol.transport
      QUIC.rearm_stream(%QUIC{quic_transport | stream: stream_handle})

      Logger.debug(
        "HTTP/3 new stream: handle=#{inspect(stream_handle)}, unidirectional=#{unidirectional?}"
      )

      {:ok, %@for{protocol | streams: Map.put(streams, stream_handle, stream)}, []}
    end
  end
end
