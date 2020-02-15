defmodule Ankh.HTTP do
  @moduledoc """
  Ankh HTTP public API
  """

  @typedoc "HTTP host"
  @type host :: String.t()

  @typedoc "HTTP method"
  @type method :: String.t()

  @typedoc "HTTP path"
  @type path :: String.t()

  @typedoc "HTTP scheme"
  @type scheme :: String.t()

  @typedoc "HTTP status"
  @type status :: String.t()

  @typedoc "HTTP body"
  @type body :: iodata()

  @typedoc "HTTP Header name"
  @type header_name :: String.t()

  @typedoc "HTTP Header value"
  @type header_value :: String.t()

  @typedoc "HTTP Header"
  @type header :: {header_name(), header_value()}

  alias Ankh.{HTTP, HTTP2, Protocol, Transport}
  alias HTTP.{Request, Response}

  @doc """
  Accepts an HTTP connection

  After accepting the connection, `stream` will receive requests from the client and `respond`
  can be used to send replies.
  """
  @spec accept(URI.t(), Transport.t(), keyword) :: {:ok, Protocol.t()} | {:error, any()}
  def accept(uri, socket, options \\ []) do
    with {:ok, protocol} <- HTTP2.new(options),
         {:ok, protocol} <- HTTP2.accept(protocol, uri, socket, options),
         do: {:ok, protocol}
  end

  @doc """
  Establishes an HTTP connection to a server

  After establishing the connection, `request` can be user to send request to the server and
  `stream` can be used to receive receive responses.
  """
  @spec connect(URI.t(), keyword) :: {:ok, Protocol.t()} | {:error, any()}
  def connect(uri, options \\ []) do
    with {:ok, protocol} <- HTTP2.new(options),
         {:ok, protocol} <- HTTP2.connect(protocol, uri, options),
         do: {:ok, protocol}
  end

  @doc """
  Sends a request to a server

  Needs a connection to be established via `connect` beforehand.
  """
  @spec request(Protocol.t(), Request.t()) ::
          {:ok, Protocol.t(), Protocol.request_reference()} | {:error, any()}
  def request(protocol, request) do
    HTTP2.request(protocol, request)
  end

  @doc """
  Sends a response to a client request

  Needs a connection to be accepted via `accept` beforehand.
  """
  @spec respond(Protocol.t(), Protocol.request_reference(), Response.t()) ::
          {:ok, Protocol.t()} | {:error, any()}
  def respond(protocol, reference, response) do
    HTTP2.respond(protocol, reference, response)
  end

  @doc """
  Receives data form the the other and and returns responses
  """
  @spec stream(Protocol.t(), any()) :: {:ok, Protocol.t(), any()}
  def stream(protocol, msg) do
    HTTP2.stream(protocol, msg)
  end

  @doc """
  Closes the underlying connection
  """
  @spec close(Protocol.t()) :: :ok | {:error, any()}
  def close(protocol) do
    HTTP2.close(protocol)
  end
end
