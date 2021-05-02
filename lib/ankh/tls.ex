defmodule Ankh.TLS do
  @moduledoc "TLS transport module"

  require Logger

  alias Ankh.Transport

  @opaque t :: %__MODULE__{socket: :ssl.socket()}
  defstruct socket: nil

  defimpl Transport do
    @default_connect_options binary: true,
                             active: false,
                             secure_renegotiate: true,
                             cacertfile: CAStore.file_path()

    def connect(tls, %URI{host: host, port: port}, timeout, options \\ []) do
      hostname = String.to_charlist(host)
      options = Keyword.merge(options, @default_connect_options)

      with {:ok, socket} <- :ssl.connect(hostname, port, options, timeout),
           :ok <- :ssl.setopts(socket, active: :once) do
        {:ok, %{tls | socket: socket}}
      end
    end

    def accept(%{socket: socket} = tls, options \\ []) do
      options = Keyword.merge(options, active: :once)

      with :ok <- :ssl.controlling_process(socket, self()),
           :ok <- :ssl.setopts(socket, options) do
        {:ok, %{tls | socket: socket}}
      end
    end

    def send(%{socket: socket}, data), do: :ssl.send(socket, data)

    def recv(%{socket: socket}, size, timeout), do: :ssl.recv(socket, size, timeout)

    def close(%{socket: socket} = tls) do
      with :ok <- :ssl.close(socket), do: {:ok, %{tls | socket: nil}}
    end

    def handle_msg(_tls, {:ssl, socket, data}) do
      with :ok <- :ssl.setopts(socket, active: :once), do: {:ok, data}
    end

    def handle_msg(_tls, {:ssl_error, _socket, reason}), do: {:error, reason}
    def handle_msg(_tls, {:ssl_closed, _socket}), do: {:error, :closed}
    def handle_msg(_tls, msg), do: {:other, msg}

    def negotiated_protocol(%{socket: socket}), do: :ssl.negotiated_protocol(socket)
  end
end
