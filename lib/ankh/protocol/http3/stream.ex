defmodule Ankh.Protocol.HTTP3.Stream do
  @moduledoc """
  Per-QUIC-stream state tracker for HTTP/3 (RFC 9114).

  Each QUIC stream used by the HTTP/3 layer is represented by one
  `#{__MODULE__}` struct.  The struct travels through a well-defined lifecycle:

  ## Lifecycle

  ### Creation

  Use `new_request/1` when the local side opens a new bidirectional request
  stream (client-initiated).  Use `new_incoming/2` when a stream arrives from
  the remote peer; pass `unidirectional? = false` for a bidirectional request
  stream and `unidirectional? = true` for a unidirectional stream whose kind
  is not yet known.

  Both functions assign a fresh Elixir `reference()` (via `make_ref/0`) that
  can be used to correlate the stream across the rest of the connection.

  ### Unidirectional stream kind identification

  Unidirectional streams start with kind `:unknown_unidirectional`.  When the
  first byte of the stream body is received, call `identify_kind/2` with that
  byte to resolve the kind:

    * `0x00` → `:control`          (HTTP/3 control stream, RFC 9114 §6.2.1)
    * `0x01` → `:push`             (server-push stream,    RFC 9114 §4.6)
    * `0x02` → `:qpack_encoder`    (QPACK encoder stream,  RFC 9204 §4.2)
    * `0x03` → `:qpack_decoder`    (QPACK decoder stream,  RFC 9204 §4.2)
    * anything else → `:unknown_unidirectional` (must be ignored per RFC 9114 §6.2)

  `identify_kind/2` is a no-op when the stream already has kind `:request`.

  ### Incoming data

  Raw bytes received from the QUIC layer are accumulated with `append/2`.  The
  frame parser (see `Ankh.Protocol.HTTP3.Frame`) should consume the buffer and
  pass any unconsumed remainder back to `consume_buffer/2` so it is retained
  for the next delivery.

  ### FIN / half-close handling

  QUIC streams support independent half-closes on each side:

    * `remote_fin/1` — call when the peer signals `peer_send_shutdown` (it has
      finished sending).  Transitions `:open → :half_closed_remote` and
      `:half_closed_local → :closed`.
    * `local_fin/1` — call after sending a FIN (e.g. via
      `:quicer.shutdown_stream/1`).  Transitions `:open → :half_closed_local`
      and `:half_closed_remote → :closed`.

  States that are already past the relevant half-close are left unchanged.

  ### Terminal state

  `closed?/1` returns `true` once the stream reaches `:closed`.
  `remote_open?/1` returns `true` while the remote side has not yet sent a FIN
  (states `:open` and `:half_closed_local`), indicating that more data or
  headers may still arrive.

  ## Frame parsing

  This module deliberately does **not** parse HTTP/3 frames.  Frame encoding
  and decoding belong in `Ankh.Protocol.HTTP3.Frame`.
  """

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @typedoc """
  HTTP/3 stream states, mirroring the QUIC stream half-close model.

    * `:idle`                — stream struct created but not yet active.
    * `:open`                — both sides may send and receive.
    * `:half_closed_local`   — local side has sent FIN; remote may still send.
    * `:half_closed_remote`  — remote side has sent FIN; local may still send.
    * `:closed`              — both sides have finished; no further data.
  """
  @type state ::
          :idle
          | :open
          | :half_closed_local
          | :half_closed_remote
          | :closed

  @typedoc """
  Categorises a QUIC stream by its HTTP/3 role.

    * `:request`                — bidirectional request/response stream
                                  (RFC 9114 §6.1).
    * `:control`                — unidirectional HTTP/3 control stream,
                                  stream-type byte `0x00` (RFC 9114 §6.2.1).
    * `:push`                   — unidirectional server-push stream,
                                  stream-type byte `0x01` (RFC 9114 §4.6).
    * `:qpack_encoder`          — unidirectional QPACK encoder stream,
                                  stream-type byte `0x02` (RFC 9204 §4.2).
    * `:qpack_decoder`          — unidirectional QPACK decoder stream,
                                  stream-type byte `0x03` (RFC 9204 §4.2).
    * `:unknown_unidirectional` — unidirectional stream whose type byte has
                                  not yet been received or is not a
                                  recognised value.
    * `:unknown`                — kind not yet determined (initial value).
  """
  @type stream_kind ::
          :request
          | :control
          | :qpack_encoder
          | :qpack_decoder
          | :push
          | :unknown_unidirectional
          | :unknown

  @typedoc "Per-QUIC-stream HTTP/3 state struct."
  @type t :: %__MODULE__{
          handle: :quicer.stream_handle() | nil,
          reference: reference() | nil,
          state: state(),
          kind: stream_kind(),
          buffer: binary(),
          recv_headers: boolean(),
          send_headers: boolean()
        }

  defstruct handle: nil,
            reference: nil,
            state: :idle,
            kind: :unknown,
            buffer: <<>>,
            recv_headers: false,
            send_headers: false

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new client-opened request stream for the given QUIC stream handle.

  The returned struct has:

    * `kind`      = `:request`
    * `state`     = `:open`
    * `reference` = a fresh `reference()` from `make_ref/0`

  ## Example

      iex> stream = #{__MODULE__}.new_request(some_handle)
      iex> stream.kind
      :request
      iex> stream.state
      :open
  """
  @spec new_request(handle :: :quicer.stream_handle()) :: t()
  def new_request(handle) do
    %__MODULE__{
      handle: handle,
      reference: make_ref(),
      state: :open,
      kind: :request
    }
  end

  @doc """
  Creates a new server-received (incoming) stream for the given QUIC stream handle.

  When `unidirectional?` is `true`, the kind is set to `:unknown_unidirectional`
  because the stream-type byte has not yet arrived.  When `unidirectional?` is
  `false`, the stream is a bidirectional request stream and the kind is set to
  `:request` immediately.

  In both cases the state is `:open` and a fresh `reference()` is assigned.

  ## Examples

      iex> stream = #{__MODULE__}.new_incoming(some_handle, false)
      iex> stream.kind
      :request

      iex> stream = #{__MODULE__}.new_incoming(some_handle, true)
      iex> stream.kind
      :unknown_unidirectional
  """
  @spec new_incoming(handle :: :quicer.stream_handle(), unidirectional? :: boolean()) :: t()
  def new_incoming(handle, false = _unidirectional?) do
    %__MODULE__{
      handle: handle,
      reference: make_ref(),
      state: :open,
      kind: :request
    }
  end

  def new_incoming(handle, true = _unidirectional?) do
    %__MODULE__{
      handle: handle,
      reference: make_ref(),
      state: :open,
      kind: :unknown_unidirectional
    }
  end

  # ---------------------------------------------------------------------------
  # Kind identification
  # ---------------------------------------------------------------------------

  @doc """
  Resolves the kind of a unidirectional stream from its first stream-type byte.

  The mapping from wire byte to kind atom is defined by RFC 9114 §6.2 and
  RFC 9204 §4.2:

    * `0x00` → `:control`
    * `0x01` → `:push`
    * `0x02` → `:qpack_encoder`
    * `0x03` → `:qpack_decoder`
    * other  → `:unknown_unidirectional` (extension / reserved stream type)

  This function is a **no-op** when the stream kind is already `:request`;
  request streams are bidirectional and do not carry a stream-type prefix.

  ## Examples

      iex> stream = #{__MODULE__}.new_incoming(handle, true)
      iex> #{__MODULE__}.identify_kind(stream, 0x00).kind
      :control

      iex> #{__MODULE__}.identify_kind(stream, 0x02).kind
      :qpack_encoder

      iex> #{__MODULE__}.identify_kind(stream, 0xFF).kind
      :unknown_unidirectional
  """
  @spec identify_kind(t(), stream_type_byte :: non_neg_integer()) :: t()
  def identify_kind(%__MODULE__{kind: :request} = stream, _stream_type_byte), do: stream

  def identify_kind(%__MODULE__{} = stream, stream_type_byte) do
    kind =
      case stream_type_byte do
        0x00 -> :control
        0x01 -> :push
        0x02 -> :qpack_encoder
        0x03 -> :qpack_decoder
        _ -> :unknown_unidirectional
      end

    %{stream | kind: kind}
  end

  # ---------------------------------------------------------------------------
  # Buffer management
  # ---------------------------------------------------------------------------

  @doc """
  Appends `data` to the stream's receive buffer.

  Call this each time the QUIC layer delivers bytes for this stream.  The
  accumulated buffer is then available for the frame parser to consume.

  ## Example

      iex> stream = #{__MODULE__}.new_request(handle)
      iex> stream = #{__MODULE__}.append(stream, <<0x01, 0x05>>)
      iex> stream.buffer
      <<0x01, 0x05>>
      iex> stream = #{__MODULE__}.append(stream, <<"hello">>)
      iex> stream.buffer
      <<0x01, 0x05, "hello">>
  """
  @spec append(t(), binary()) :: t()
  def append(%__MODULE__{buffer: buffer} = stream, data) when is_binary(data) do
    %{stream | buffer: buffer <> data}
  end

  @doc """
  Replaces the stream buffer with `remainder`.

  Call this after the frame parser has consumed one or more complete frames
  from `stream.buffer`, passing whatever bytes were not consumed.  This keeps
  partial frames available for the next delivery without re-appending the
  already-parsed bytes.

  ## Example

      iex> stream = #{__MODULE__}.append(stream, <<0x00, 0x03, "abc", 0xFF>>)
      iex> stream = #{__MODULE__}.consume_buffer(stream, <<0xFF>>)
      iex> stream.buffer
      <<0xFF>>
  """
  @spec consume_buffer(t(), binary()) :: t()
  def consume_buffer(%__MODULE__{} = stream, remainder) when is_binary(remainder) do
    %{stream | buffer: remainder}
  end

  # ---------------------------------------------------------------------------
  # FIN / half-close transitions
  # ---------------------------------------------------------------------------

  @doc """
  Records that the remote peer has finished sending on this stream.

  This is typically triggered by a `{:quic, :peer_send_shutdown, …}` message
  from the quicer NIF.

  State transitions:

    * `:open`               → `:half_closed_remote`
    * `:half_closed_local`  → `:closed`
    * all other states      → unchanged

  ## Examples

      iex> stream = #{__MODULE__}.new_request(handle)
      iex> #{__MODULE__}.remote_fin(stream).state
      :half_closed_remote

      iex> stream = %{stream | state: :half_closed_local}
      iex> #{__MODULE__}.remote_fin(stream).state
      :closed
  """
  @spec remote_fin(t()) :: t()
  def remote_fin(%__MODULE__{state: :open} = stream),
    do: %{stream | state: :half_closed_remote}

  def remote_fin(%__MODULE__{state: :half_closed_local} = stream),
    do: %{stream | state: :closed}

  def remote_fin(%__MODULE__{} = stream), do: stream

  @doc """
  Records that the local side has finished sending on this stream.

  Call this after successfully writing a FIN to the QUIC layer (e.g. via
  `:quicer.shutdown_stream/1` or the `fin` flag on the last `:quicer.send/3`).

  State transitions:

    * `:open`                → `:half_closed_local`
    * `:half_closed_remote`  → `:closed`
    * all other states       → unchanged

  ## Examples

      iex> stream = #{__MODULE__}.new_request(handle)
      iex> #{__MODULE__}.local_fin(stream).state
      :half_closed_local

      iex> stream = %{stream | state: :half_closed_remote}
      iex> #{__MODULE__}.local_fin(stream).state
      :closed
  """
  @spec local_fin(t()) :: t()
  def local_fin(%__MODULE__{state: :open} = stream),
    do: %{stream | state: :half_closed_local}

  def local_fin(%__MODULE__{state: :half_closed_remote} = stream),
    do: %{stream | state: :closed}

  def local_fin(%__MODULE__{} = stream), do: stream

  # ---------------------------------------------------------------------------
  # State predicates
  # ---------------------------------------------------------------------------

  @doc """
  Returns `true` when the stream has reached the `:closed` state.

  A closed stream has had both its send and receive sides terminated; no
  further data or frames should be processed on it.

  ## Example

      iex> stream = #{__MODULE__}.new_request(handle)
      iex> #{__MODULE__}.closed?(stream)
      false
      iex> stream = stream |> #{__MODULE__}.remote_fin() |> #{__MODULE__}.local_fin()
      iex> #{__MODULE__}.closed?(stream)
      true
  """
  @spec closed?(t()) :: boolean()
  def closed?(%__MODULE__{state: :closed}), do: true
  def closed?(%__MODULE__{}), do: false

  @doc """
  Returns `true` when the remote side of the stream is still open.

  The remote side is considered open in states `:open` and
  `:half_closed_local`, meaning the peer has not yet sent a FIN and may still
  deliver headers, data, or other frames.

  ## Examples

      iex> stream = #{__MODULE__}.new_request(handle)
      iex> #{__MODULE__}.remote_open?(stream)
      true

      iex> #{__MODULE__}.remote_open?(#{__MODULE__}.remote_fin(stream))
      false
  """
  @spec remote_open?(t()) :: boolean()
  def remote_open?(%__MODULE__{state: state}) when state in [:open, :half_closed_local],
    do: true

  def remote_open?(%__MODULE__{}), do: false
end
