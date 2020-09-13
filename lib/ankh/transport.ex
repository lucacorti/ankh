defprotocol Ankh.Transport do
  @moduledoc """
  Transport behavior
  """

  @typedoc "Transport socket"
  @type t :: struct()

  @typedoc "Size"
  @type size :: non_neg_integer()

  @typedoc "Socket"
  @type socket :: any()

  @typedoc """
  Transport options
  """
  @type options :: Keyword.t()

  @doc """
  Accepts a client connection
  """
  @spec accept(t, Keyword.t()) :: {:ok, t()} | {:error, any()}
  def accept(transport, options)

  @doc """
  Closes the connection
  """
  @spec close(t()) :: {:ok, t()} | {:error, any()}
  def close(transport)

  @doc """
  Connects to an host
  """
  @spec connect(t(), URI.t(), timeout(), options()) :: {:ok, t()} | {:error, any()}
  def connect(transport, uri, timeout, options)

  @doc """
  Sends data
  """
  @spec send(t(), iodata()) :: :ok | {:error, any()}
  def send(transport, data)

  @doc """
  Receives data
  """
  @spec recv(t(), size(), timeout()) :: {:ok, iodata()} | {:error, any()}
  def recv(transport, size, timeout)

  @doc """
  Handles transport messages
  """
  @spec handle_msg(t(), any()) :: {:ok, iodata()} | {:error, any()}
  def handle_msg(transport, message)

  @doc """
  Returns the transport negotiated protocol if any, nil otherwise
  """
  @spec negotiated_protocol(t()) :: {:ok, String.t()} | {:error, :protocol_not_negotiated}
  def negotiated_protocol(transport)
end
