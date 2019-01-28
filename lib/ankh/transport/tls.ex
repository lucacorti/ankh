defmodule Ankh.Transport.TLS do
  @moduledoc """
  TLS transport module
  """

  alias Ankh.Transport

  @behaviour Transport

  @default_connect_options binary: true,
                           active: false,
                           versions: [:"tlsv1.2"],
                           secure_renegotiate: true,
                           client_renegotiation: false,
                           ciphers: ["ECDHE-ECDSA-AES128-SHA256", "ECDHE-ECDSA-AES128-SHA"],
                           alpn_advertised_protocols: ["h2"],
                           cacerts: :certifi.cacerts()

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  @impl Transport
  def connect(%URI{host: host, port: port}, receiver, options \\ []) do
    hostname = String.to_charlist(host)
    options = Keyword.merge(options, @default_connect_options)

    with {:ok, socket} <- :ssl.connect(hostname, port, options),
         :ok <- :ssl.controlling_process(socket, receiver),
         :ok <- :ssl.setopts(socket, active: :once),
         :ok <- :ssl.send(socket, @preface) do
      {:ok, socket}
    else
      {:error, reason} ->
        {:error, :ssl.format_error(reason)}
    end
  end

  @impl Transport
  def accept(socket, receiver, options \\ []) do
    options = Keyword.merge(options, active: :once)
    preface = @preface

    with {:ok, ^preface} <- :ssl.recv(socket, 24),
         :ok <- :ssl.controlling_process(socket, receiver),
         :ok <- :ssl.setopts(socket, options) do
      {:ok, socket}
    else
      {:error, reason} ->
        {:error, :ssl.format_error(reason)}

      _ ->
        {:error, :protocol_error}
    end
  end

  @impl Transport
  def send(socket, data) do
    with :ok <- :ssl.send(socket, data) do
      :ok
    else
      {:error, reason} ->
        {:error, :ssl.format_error(reason)}
    end
  end

  @impl Transport
  def recv(socket, size) do
    with {:ok, data} <- :ssl.recv(socket, size) do
      {:ok, data}
    else
      {:error, reason} ->
        {:error, :ssl.format_error(reason)}
    end
  end

  @impl Transport
  def close(socket) do
    with :ok <- :ssl.close(socket) do
      :ok
    else
      {:error, reason} ->
        {:error, :ssl.format_error(reason)}
    end
  end

  @impl Transport
  def handle_msg({:ssl, socket, data}) do
    with :ok <- :ssl.setopts(socket, active: :once) do
      {:data, data}
    else
      {:error, reason} ->
        {:error, :ssl.format_error(reason)}
    end
  end

  @impl Transport
  def handle_msg({:ssl_error, _socket, reason}), do: {:error, :ssl.format_error(reason)}

  @impl Transport
  def handle_msg({:ssl_closed, _socket}), do: :closed
end
