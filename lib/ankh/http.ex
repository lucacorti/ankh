defmodule Ankh.HTTP do
  @moduledoc """
  HTTP public interface

  This module implements `Ankh` public APIs and provides protocol negotiation.

  ## Protocol negotiation for `https://`

  When connecting to an `https://` URI, the `:protocols` option controls which
  HTTP version is attempted and in what order:

    * `[:h2, :"http/1.1"]` — TLS/TCP only; ALPN negotiates between HTTP/2 and
      HTTP/1.1 (this is the **default**).
    * `[:h3]` — QUIC only; returns an error if the QUIC handshake fails.
    * `[:h3, :h2, :"http/1.1"]` — QUIC/HTTP3 is tried first; if it fails
      (e.g. UDP is blocked by a firewall), the connection falls back to TLS
      and ALPN negotiates between HTTP/2 and HTTP/1.1.

  HTTP/3 runs exclusively over QUIC. Use `https://` with `protocols: [:h3]`
  (or `protocols: [:h3, :h2, :"http/1.1"]` for automatic fallback).

  ## Examples

      # HTTP/2 or HTTP/1.1 over TLS (default)
      Ankh.HTTP.connect(URI.parse("https://example.com"), [])

      # HTTP/3 over QUIC only
      Ankh.HTTP.connect(URI.parse("https://example.com"), protocols: [:h3])

      # HTTP/3 preferred, fall back to TLS automatically
      Ankh.HTTP.connect(URI.parse("https://example.com"), protocols: [:h3, :h2, :"http/1.1"])

  """

  alias Ankh.{HTTP, Protocol, Transport}
  alias Ankh.HTTP.{Error, Request, Response}
  alias Ankh.Protocol.{HTTP1, HTTP2, HTTP3}
  alias Ankh.Transport.{QUIC, TCP, TLS}

  @typedoc "HTTP body"
  @type body :: iodata()

  @typedoc "HTTP Header name"
  @type header_name :: String.t()

  @typedoc "HTTP Header value"
  @type header_value :: String.t()

  @typedoc "HTTP Header"
  @type header :: {header_name(), header_value()}

  @typedoc "HTTP Headers"
  @type headers :: [header()]

  @type complete :: boolean()

  @type response ::
          {:data, reference(), iodata(), complete()}
          | {:headers | :push_promise, reference(), headers(), complete()}
          | {:error, reference, Error.reason(), complete()}

  @doc """
  Accepts an HTTP connection

  After accepting the connection, `stream` will receive requests from the client and `respond`
  can be used to send replies.
  """
  @spec accept(URI.t(), Transport.socket(), Transport.options()) ::
          {:ok, Protocol.t()} | {:error, any()}
  def accept(uri, socket, options \\ [])

  def accept(%URI{scheme: "http"} = uri, socket, options),
    do: Protocol.accept(%HTTP1{}, uri, %TCP{}, socket, options)

  def accept(%URI{scheme: "https"} = uri, socket, options) when is_port(socket) do
    with {:ok, negotiated_protocol} <- Transport.negotiated_protocol(%TLS{socket: socket}),
         {:ok, protocol} <- protocol_for_id(negotiated_protocol) do
      Protocol.accept(protocol, uri, %TLS{}, socket, options)
    end
  end

  def accept(%URI{scheme: "https"} = uri, socket, options) when is_reference(socket) do
    # QUIC connection — check negotiated ALPN and dispatch to HTTP/3.
    with {:ok, negotiated_protocol} <-
           Transport.negotiated_protocol(%QUIC{connection: socket}),
         {:ok, protocol} <- protocol_for_id(negotiated_protocol) do
      Protocol.accept(protocol, uri, %QUIC{}, socket, options)
    end
  end

  def accept(_uri, _socket, _options), do: {:error, :unsupported_uri_scheme}

  @doc """
  Establishes an HTTP connection to a server

  After establishing the connection, `request` can be user to send request
   and `stream` can be used to receive responses from the server.
  """
  @spec connect(URI.t(), Transport.options()) ::
          {:ok, Protocol.t()} | {:error, any()}
  def connect(uri, options \\ [])

  def connect(%URI{scheme: "http"} = uri, options) do
    {timeout, options} = Keyword.pop(options, :timeout, 5_000)

    with {:ok, transport} <- Transport.connect(%TCP{}, uri, timeout, options) do
      Protocol.connect(%HTTP1{}, uri, transport, options)
    end
  end

  def connect(%URI{scheme: "https"} = uri, options) do
    {protocols, options} = Keyword.pop(options, :protocols, [:h2, :"http/1.1"])

    if :h3 in protocols do
      tls_fallback = Enum.filter(protocols, &(&1 in [:h2, :"http/1.1"]))

      case connect_quic(uri, options) do
        {:ok, _} = ok ->
          ok

        {:error, _} when tls_fallback != [] ->
          connect_tls(uri, options, tls_fallback)

        {:error, _} = error ->
          error
      end
    else
      connect_tls(uri, options, protocols)
    end
  end

  def connect(_uri, _options), do: {:error, :unsupported_uri_scheme}

  # Establishes an HTTP/3 connection over QUIC.
  #
  # quicer's alpn() type is an Erlang string() (charlist), not a binary.
  # peer_unidi_stream_count: 3 lets the server open the three unidirectional
  # streams required by HTTP/3 (control, QPACK encoder, QPACK decoder).
  defp connect_quic(%URI{} = uri, options) do
    {timeout, options} = Keyword.pop(options, :timeout, 5_000)

    quic_options =
      [alpn: [~c"h3"], verify: :verify_peer, peer_unidi_stream_count: 3]
      |> Keyword.merge(
        Keyword.take(options, [:cacertfile, :certfile, :keyfile, :password, :verify])
      )

    # quicer returns a 3-tuple for transport-level failures (e.g. DNS errors,
    # TLS handshake failures).  Normalise to a 2-tuple so the caller's case
    # clauses ({:error, _}) always see a consistent shape.
    case Transport.connect(%QUIC{}, uri, timeout, quic_options) do
      {:ok, transport} -> Protocol.connect(%HTTP3{}, uri, transport, options)
      {:error, reason, _props} -> {:error, reason}
      {:error, _} = error -> error
    end
  end

  # Establishes an HTTP/1.1 or HTTP/2 connection over TLS.
  #
  # `protocols` is a list of atoms from `[:h2, :"http/1.1"]` that are
  # converted to their ALPN token strings and advertised to the server.
  defp connect_tls(%URI{} = uri, options, protocols) do
    alpn_tokens = Enum.map(protocols, &protocol_to_alpn_token/1)

    {:ok, tls_options} = Plug.SSL.configure(cipher_suite: :strong, key: nil, cert: nil)

    tls_options =
      tls_options
      |> Keyword.take([:versions, :ciphers, :eccs])
      |> Keyword.merge(alpn_advertised_protocols: alpn_tokens)

    {timeout, options} =
      options
      |> Keyword.merge(tls_options)
      |> Keyword.pop(:timeout, 5_000)

    with {:ok, transport} <- Transport.connect(%TLS{}, uri, timeout, options),
         {:ok, negotiated_protocol} <- Transport.negotiated_protocol(transport),
         {:ok, protocol} <- protocol_for_id(negotiated_protocol) do
      Protocol.connect(protocol, uri, transport, options)
    end
  end

  defp protocol_to_alpn_token(:h2), do: "h2"
  defp protocol_to_alpn_token(:"http/1.1"), do: "http/1.1"

  defp protocol_for_id("http/1.1"), do: {:ok, %HTTP1{}}
  defp protocol_for_id("h2"), do: {:ok, %HTTP2{}}
  defp protocol_for_id("h3"), do: {:ok, %HTTP3{}}
  defp protocol_for_id(_id), do: {:error, :unsupported_protocol_identifier}

  @doc """
  Sends a request to a server

  Needs a connection to be established via `connect` beforehand.
  """
  @spec request(Protocol.t(), Request.t()) ::
          {:ok, Protocol.t(), Protocol.request_ref()} | {:error, any()}
  def request(protocol, request), do: Protocol.request(protocol, request)

  @doc """
  Sends a response to a client request

  Needs a connection to be accepted via `accept` beforehand.
  """
  @spec respond(Protocol.t(), Protocol.request_ref(), Response.t()) ::
          {:ok, Protocol.t()} | {:error, any()}
  def respond(protocol, reference, response),
    do: Protocol.respond(protocol, reference, response)

  @doc """
  Receives a transport message and returns responses
  """
  @spec stream(Protocol.t(), Transport.msg()) :: {:ok, Protocol.t(), any()} | {:error, any()}
  def stream(%{transport: transport} = protocol, msg) do
    with {:ok, data} <- Transport.handle_msg(transport, msg) do
      stream_data(protocol, data)
    end
  end

  @doc """
  Receives data and returns responses
  """
  @spec stream_data(Protocol.t(), Transport.data()) ::
          {:ok, Protocol.t(), any()} | {:error, any()}
  def stream_data(protocol, data) do
    Protocol.stream(protocol, data)
  end

  @doc """
  Closes the underlying connection
  """
  @spec close(Protocol.t()) :: :ok | {:error, any()}
  def close(%{transport: transport} = protocol) do
    with {:ok, transport} <- Transport.close(transport),
         do: {:ok, %{protocol | transport: transport}}
  end

  @doc """
  Reports a connection error
  """
  @spec error(Protocol.t()) :: :ok | {:error, any()}
  def error(protocol), do: Protocol.error(protocol)

  @doc false
  @spec put_header(Request.t() | Response.t(), HTTP.header_name(), HTTP.header_value()) ::
          Request.t() | Response.t()
  def put_header(%{headers: headers} = response, name, value),
    do: %{response | headers: [{String.downcase(name), value} | headers]}

  @doc false
  @spec put_headers(Request.t() | Response.t(), HTTP.headers()) :: Request.t() | Response.t()
  def put_headers(response, headers),
    do:
      Enum.reduce(headers, response, fn {header, value}, acc ->
        put_header(acc, header, value)
      end)

  @doc false
  @spec put_trailer(Request.t() | Response.t(), HTTP.header_name(), HTTP.header_value()) ::
          Request.t() | Response.t()
  def put_trailer(%{trailers: trailers} = response, name, value),
    do: %{response | trailers: [{String.downcase(name), value} | trailers]}

  @doc false
  @spec put_trailers(Request.t() | Response.t(), HTTP.headers()) :: Request.t() | Response.t()
  def put_trailers(response, trailers) do
    Enum.reduce(trailers, response, fn {header, value}, acc ->
      put_trailer(acc, header, value)
    end)
  end

  @doc false
  @spec validate_body(Request.t() | Response.t()) :: {:ok, Request.t() | Response.t()} | :error
  def validate_body(%{body: body} = request) do
    with content_length when not is_nil(content_length) <-
           request
           |> fetch_header_values("content-length")
           |> List.first(),
         data_length when data_length != content_length <-
           body
           |> IO.iodata_length()
           |> Integer.to_string() do
      :error
    else
      _ ->
        {:ok, request}
    end
  end

  @doc false
  @spec fetch_header_values(Request.t() | Response.t(), HTTP.header_name()) :: [
          HTTP.header_value()
        ]
  def fetch_header_values(%{headers: headers}, name), do: fetch_values(headers, name)

  @doc false
  @spec fetch_trailer_values(Request.t() | Response.t(), HTTP.header_name()) :: [
          HTTP.header_value()
        ]
  def fetch_trailer_values(%{trailers: trailers}, name), do: fetch_values(trailers, name)

  defp fetch_values(headers, name) do
    headers
    |> Enum.reduce([], fn
      {^name, value}, acc ->
        [value | acc]

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  @spec validate_trailers(headers(), boolean()) :: :ok | {:error, :protocol_error}
  def validate_trailers([], _strict), do: :ok

  def validate_trailers([{":" <> _trailer, _value} | _rest], _strict),
    do: {:error, :protocol_error}

  def validate_trailers([{name, _value} | rest], strict) do
    if header_name_valid?(name, strict) do
      validate_trailers(rest, strict)
    else
      {:error, :protocol_error}
    end
  end

  @spec header_name_valid?(header_name(), boolean()) :: boolean()
  def header_name_valid?(name, false = _strict) do
    name
    |> String.downcase()
    |> header_name_valid?(true)
  end

  def header_name_valid?(name, true = _strict),
    do: name =~ ~r(^[[:lower:][:digit:]\!\#\$\%\&\'\*\+\-\.\^\_\`\|\~]+$)
end
