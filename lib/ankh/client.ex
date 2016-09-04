defmodule Ankh.Client do
  use GenServer

  alias Ankh.{Client, Connection, Frame}
  alias Ankh.Frame.{Headers}

  def start_link(%URI{} = uri, options \\ []) do
    GenServer.start_link(__MODULE__, uri, options)
  end

  def init(uri) do
    {:ok, %{uri: uri, last_stream_id: -1}}
  end

  def delete(address, headers \\ []) do
    request("DELETE", address, headers)
  end

  def get(address, headers \\ []) do
    request("GET", address, headers)
  end

  def post(address, headers \\ []) do
    request("POST", address, headers)
  end

  def put(address, headers \\ []) do
    request("PUT", address, headers)
  end

  def request(method, address, headers \\ []) do
    uri = parse_address(address)
    via = {:via, Client.Registry, uri}

    with :undefined <- Client.Registry.whereis_name(uri) do
      options = [name: via]
      {:ok, pid} = Supervisor.start_child(Client.Supervisor, [uri, options])
    end

    full_headers = [{":method", method} | headers_for_uri(uri)] ++ headers
    GenServer.call(via, {:request, method, uri, full_headers})
  end

  def handle_call({:request, method, uri, headers}, _from,
  %{last_stream_id: last_stream_id} = state) do
    stream_id = last_stream_id + 2
    via = {:via, Connection.Registry, uri}

    with :undefined <- Connection.Registry.whereis_name(uri) do
      options = [name: via]
      Supervisor.start_child(Connection.Supervisor, [uri, options])
    end

    with :ok <- do_request(via, stream_id, method, headers) do
      {:reply, :ok, %{state | last_stream_id: stream_id}}
    else
      error ->
        {:reply, error, state}
    end
  end

  defp do_request(connection, stream_id, "GET", headers) do
    Connection.send(connection, %Frame{stream_id: stream_id,
      type: :headers, flags: %Headers.Flags{end_headers: true},
      payload: %Headers.Payload{header_block_fragment: headers}
    })
  end

  defp do_request(_connection, _stream_id, method, _headers) do
    raise "Method \"#{method}\" not implemented yet."
  end

  defp parse_address(address) when is_binary(address) do
    address
    |> URI.parse
    |> parse_address
  end

  defp parse_address(%URI{scheme: nil}) do
    raise "No scheme present in address"
  end

  defp parse_address(%URI{host: nil}) do
    raise "No hostname present in address"
  end

  defp parse_address(%URI{scheme: "http"}) do
    raise "Plaintext HTTP is not supported"
  end

  defp parse_address(%URI{} = uri), do: uri

  defp headers_for_uri(%URI{path: nil} = uri) do
    headers_for_uri(%URI{uri | path: "/"})
  end

  defp headers_for_uri(%URI{scheme: scheme, authority: authority, path: path})
  do
    [{":scheme", scheme}, {":authority", authority}, {":path", path}]
  end
end
