defmodule Ankh.Transport.TLS do
  @moduledoc """
  TLS transport module
  """

  require Logger

  alias Ankh.Transport

  @behaviour Transport

  @default_connect_options binary: true,
                           active: false,
                           secure_renegotiate: true,
                           cacertfile: CAStore.file_path()

  @impl Transport
  def connect(%URI{host: host, port: port}, options \\ []) do
    hostname = String.to_charlist(host)
    options = Keyword.merge(options, @default_connect_options)

    with {:ok, socket} <- :ssl.connect(hostname, port, options),
         :ok <- :ssl.setopts(socket, active: :once) do
      {:ok, socket}
    end
  end

  @impl Transport
  def accept(socket, options \\ []) do
    options = Keyword.merge(options, active: :once)

    with :ok <- :ssl.controlling_process(socket, self()),
         :ok <- :ssl.setopts(socket, options) do
      {:ok, socket}
    end
  end

  @impl Transport
  def send(socket, data) do
    with :ok <- :ssl.send(socket, data), do: Logger.debug(fn -> "SENT #{inspect(data)}" end)
  end

  @impl Transport
  def recv(socket, size), do: :ssl.recv(socket, size)

  @impl Transport
  def close(socket), do: :ssl.close(socket)

  @impl Transport
  def handle_msg({:ssl, socket, data}) do
    Logger.debug(fn -> "RECVD #{inspect(data)}" end)
    with :ok <- :ssl.setopts(socket, active: :once), do: {:ok, data}
  end

  @impl Transport
  def handle_msg({:ssl_error, _socket, reason}), do: {:error, reason}

  @impl Transport
  def handle_msg({:ssl_closed, _socket}), do: {:error, :closed}

  @impl Transport
  def handle_msg(msg), do: {:other, msg}
end
