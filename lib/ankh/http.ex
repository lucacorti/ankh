defmodule Ankh.HTTP do
  @moduledoc """
  HTTP public interface

  This module implements `Ankh` public APIs and provides protocol negotiation.
  """

  alias Ankh.{HTTP, HTTP1, HTTP2, Protocol, TCP, TLS, Transport}
  alias HTTP.{Request, Response}
  alias HTTP2.Error

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
          | {:error, reference, Error.t(), complete()}

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

  def accept(%URI{scheme: "https"} = uri, socket, options) do
    with {:ok, negotiated_protocol} <- Transport.negotiated_protocol(%TLS{socket: socket}),
         {:ok, protocol} <- protocol_for_id(negotiated_protocol),
         {:ok, protocol} <- Protocol.accept(protocol, uri, %TLS{}, socket, options),
         do: {:ok, protocol}
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

    with {:ok, transport} <- Transport.connect(%TCP{}, uri, timeout, options),
         {:ok, protocol} <- Protocol.connect(%HTTP1{}, uri, transport, options),
         do: {:ok, protocol}
  end

  def connect(%URI{scheme: "https"} = uri, options) do
    {:ok, tls_options} = Plug.SSL.configure(cipher_suite: :strong, key: nil, cert: nil)

    tls_options =
      tls_options
      |> Keyword.take([:versions, :ciphers, :eccs])
      |> Keyword.merge(alpn_advertised_protocols: ["h2", "http/1.1"])

    {timeout, options} =
      options
      |> Keyword.merge(tls_options)
      |> Keyword.pop(:timeout, 5_000)

    with {:ok, transport} <- Transport.connect(%TLS{}, uri, timeout, options),
         {:ok, negotiated_protocol} <- Transport.negotiated_protocol(transport),
         {:ok, protocol} <- protocol_for_id(negotiated_protocol),
         {:ok, protocol} <- Protocol.connect(protocol, uri, transport, options),
         do: {:ok, protocol}
  end

  def connect(_uri, _options), do: {:error, :unsupported_uri_scheme}

  defp protocol_for_id("http/1.1"), do: {:ok, %HTTP1{}}
  defp protocol_for_id("h2"), do: {:ok, %HTTP2{}}
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
  Receives data form the the peer and returns responses
  """
  @spec stream(Protocol.t(), any()) :: {:ok, Protocol.t(), any()} | {:error, any()}
  def stream(protocol, msg), do: Protocol.stream(protocol, msg)

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
