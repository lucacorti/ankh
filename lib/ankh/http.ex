defmodule Ankh.HTTP do
  @moduledoc """
  Ankh HTTP public API
  """

  alias Ankh.{HTTP, HTTP2, Protocol, Transport}
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

  @type msg_type :: :headers | :data | :push_promise

  @type complete :: boolean()

  @type msg ::
          {msg_type, reference, iodata(), complete()}
          | {:error, reference, Error.t(), complete()}

  @doc """
  Accepts an HTTP connection

  After accepting the connection, `stream` will receive requests from the client and `respond`
  can be used to send replies.
  """
  @spec accept(URI.t(), Transport.t(), Transport.options()) ::
          {:ok, Protocol.t()} | {:error, any()}
  def accept(uri, transport, options \\ []) do
    with {:ok, protocol} <- Protocol.new(%HTTP2{}, options),
         {:ok, protocol} <- Protocol.accept(protocol, uri, transport, options),
         do: {:ok, protocol}
  end

  @doc """
  Establishes an HTTP connection to a server

  After establishing the connection, `request` can be user to send request to the server and
  `stream` can be used to receive receive responses.
  """
  @spec connect(URI.t(), Transport.t(), Transport.options()) ::
          {:ok, Protocol.t()} | {:error, any()}
  def connect(uri, transport, options \\ []) do
    with {:ok, protocol} <- Protocol.new(%HTTP2{}, options),
         {:ok, protocol} <- Protocol.connect(protocol, uri, transport, options),
         do: {:ok, protocol}
  end

  @doc """
  Sends a request to a server

  Needs a connection to be established via `connect` beforehand.
  """
  @spec request(Protocol.t(), Request.t()) ::
          {:ok, Protocol.t(), Protocol.request_ref()} | {:error, any()}
  def request(protocol, request) do
    Protocol.request(protocol, request)
  end

  @doc """
  Sends a response to a client request

  Needs a connection to be accepted via `accept` beforehand.
  """
  @spec respond(Protocol.t(), Protocol.request_ref(), Response.t()) ::
          {:ok, Protocol.t()} | {:error, any()}
  def respond(protocol, reference, response) do
    Protocol.respond(protocol, reference, response)
  end

  @doc """
  Receives data form the the other and and returns responses
  """
  @spec stream(Protocol.t(), any()) :: {:ok, Protocol.t(), any()} | {:error, any()}
  def stream(protocol, msg) do
    Protocol.stream(protocol, msg)
  end

  @doc """
  Closes the underlying connection
  """
  @spec close(Protocol.t()) :: :ok | {:error, any()}
  def close(protocol) do
    Protocol.close(protocol)
  end

  @doc """
  Reports a connection error
  """
  @spec error(Protocol.t()) :: :ok | {:error, any()}
  def error(protocol) do
    Protocol.error(protocol)
  end

  @spec put_header(Request.t() | Response.t(), HTTP.header_name(), HTTP.header_value()) ::
          Request.t() | Response.t()
  def put_header(%{headers: headers} = response, name, value),
    do: %{response | headers: [{String.downcase(name), value} | headers]}

  @spec put_headers(Request.t() | Response.t(), HTTP.headers()) :: Request.t() | Response.t()
  def put_headers(response, headers),
    do:
      Enum.reduce(headers, response, fn {header, value}, acc -> put_header(acc, header, value) end)

  @spec put_trailer(Request.t() | Response.t(), HTTP.header_name(), HTTP.header_value()) ::
          Request.t() | Response.t()
  def put_trailer(%{trailers: trailers} = response, name, value),
    do: %{response | trailers: [{String.downcase(name), value} | trailers]}

  @spec put_trailers(Request.t() | Response.t(), HTTP.headers()) :: Request.t() | Response.t()
  def put_trailers(response, trailers) do
    Enum.reduce(trailers, response, fn {header, value}, acc ->
      put_trailer(acc, header, value)
    end)
  end

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

  @spec fetch_header_values(Request.t() | Response.t(), HTTP.header_name()) :: [
          HTTP.header_value()
        ]
  def fetch_header_values(%{headers: headers}, name), do: fetch_values(headers, name)

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
end
