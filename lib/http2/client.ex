defmodule Http2.Client do
  alias Http2.{Connection, Frame}
  alias Http2.Frame.{Headers}

  def delete(address, headers \\ %{}, options \\ []) do
    request("DELETE", address, headers, options)
  end

  def get(address, headers \\ %{}, options \\ []) do
    request("GET", address, headers, options)
  end

  def post(address, headers \\ %{}, options \\ []) do
    request("POST", address, headers, options)
  end

  def put(address, headers \\ %{}, options \\ []) do
    request("PUT", address, headers, options)
  end

  def request(method, address, headers \\ %{}, options \\ []) do
    uri = address
    |> URI.parse

    request_headers = headers_for_request(uri)
    |> Map.put(":method", method)
    |> Map.merge(headers)
    |> Map.to_list

    {:ok, pid} = Connection.start_link(uri.host, uri.port, options)

    Connection.send(pid, %Frame{stream_id: 1, type: :headers,
    flags: %Headers.Flags{
      end_headers: true,
    }, payload: %Headers.Payload{
      header_block_fragment: request_headers
    }})
  end

  defp headers_for_request(%URI{authority: authority, path: path}) do
    %{":scheme" => "https", ":authority" => authority, ":path" => path || "/"}
  end
end
