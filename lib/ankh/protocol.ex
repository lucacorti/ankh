defprotocol Ankh.Protocol do
  @moduledoc """
  HTTP Protocol interface

  HTTP protocol implementations like `Ankh.HTTP1` and `Ankh.HTTP2` implement this protocol
  and can be used via `Ankh.HTTP`.
  """

  alias Ankh.{HTTP, Transport}
  alias Ankh.HTTP.{Request, Response}

  @typedoc "Ankh protocol"
  @type t :: struct()

  @typedoc "Protocol options"
  @type options :: keyword()

  @typedoc "Request reference"
  @type request_ref :: reference()

  @doc """
  Accepts a client connection
  """
  @spec accept(t(), URI.t(), Transport.t(), Transport.socket(), Transport.options()) ::
          {:ok, t()} | {:error, any()}
  def accept(protocol, uri, transport, socket, options)

  @doc """
  Connects to an host
  """
  @spec connect(t(), URI.t(), Transport.t(), Transport.options()) ::
          {:ok, t()} | {:error, any()}
  def connect(protocol, uri, transport, options)

  @doc """
  Reports a connection error
  """
  @spec error(t()) :: :ok | {:error, any()}
  def error(protocol)

  @doc """
  Sends a response
  """
  @spec respond(t(), request_ref(), Response.t()) :: {:ok, t()} | {:error, any()}
  def respond(protocol, request_reference, response)

  @doc """
  Sends a request
  """
  @spec request(t(), Request.t()) :: {:ok, t(), request_ref()} | {:error, any()}
  def request(protocol, request)

  @doc """
  Handles transport messages
  """
  @spec stream(t(), any()) :: {:ok, t(), [HTTP.response()]} | {:error, any()}
  def stream(protocol, messages)
end
