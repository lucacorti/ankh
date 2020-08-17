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
end
