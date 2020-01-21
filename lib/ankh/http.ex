defmodule Ankh.HTTP do
  @moduledoc """
  Genserver implementing HTTP/2 connection management

  `Ankh.Connection` establishes the underlying TLS connection and provides
  connection and stream management, it also does frame (de)serialization and
  reassembly as needed.

  After starting the connection, received frames are sent back to the caller,
  or the process specified in the `controlling_process` startup option, as messages.
  Separate messages are sent for HEADERS, PUSH_PROMISE and DATA frames.

  Headers are always reassembled and sent back in one message to the controlling_process.
  For data frames a `data` msg is sent for each received DATA
  frame, and it is the controlling_process responsibility to reassemble incoming data.

  For both HEADERS and DATA FRAMES the end_stream flag signals if the peer is
  done with the stream or more DATA/HEADERS blocks are going to be transmitted.

  Errors are reported via `error` msg.

  See typespecs below for message types and formats.
  """

  @type status :: binary()
  @type body :: iodata()
  @type header_name :: String.t()
  @type header_value :: String.t()
  @type header :: {header_name(), header_value()}

  alias Ankh.HTTP2

  @spec accept(URI.t(), Transport.t(), keyword) :: {:ok, Protocol.t()} | {:error, any()}
  def accept(uri, socket, options \\ []) do
    with {:ok, protocol} <- HTTP2.new(options),
         {:ok, protocol} <- HTTP2.accept(protocol, uri, socket, options),
         do: {:ok, protocol}
  end

  @spec connect(URI.t(), keyword) :: {:ok, Protocol.t()} | {:error, any()}
  def connect(uri, options \\ []) do
    with {:ok, protocol} <- HTTP2.new(options),
         {:ok, protocol} <- HTTP2.connect(protocol, uri, options),
         do: {:ok, protocol}
  end

  @spec request(Protocol.t(), Request.t(), keyword) ::
          {:ok, Protocol.t(), Protocol.request_reference()} | {:error, any()}
  def request(protocol, request, options \\ []) do
    HTTP2.request(protocol, request, options)
  end

  @spec respond(Protocol.t(), Protocol.request_reference(), Response.t(), keyword) ::
          {:ok, Protocol.t()} | {:error, any()}
  def respond(protocol, reference, response, options \\ []) do
    HTTP2.respond(protocol, reference, response, options)
  end

  def stream(protocol, msg) do
    HTTP2.stream(protocol, msg)
  end

  @spec close(Protocol.t()) :: :ok | {:error, any()}
  def close(protocol) do
    HTTP2.close(protocol)
  end
end
