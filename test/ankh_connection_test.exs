defmodule AnkhTest.Connection do
  use ExUnit.Case

  alias Ankh.Frame.{Headers, Settings}
  alias Ankh.Connection

  alias AnkhTest.StreamGen

  @hostname "https://www.google.it"

  doctest Connection

  setup do
    uri = URI.parse(@hostname)
    {:ok, stream_gen} = StreamGen.start_link(:client)
    {:ok, [uri: uri, stream_gen: stream_gen]}
  end

  test "get request",
  %{uri: %URI{authority: authority} = uri, stream_gen: stream_gen} do
    opts = [receiver: self(), stream: true, ssl_options: []]
    assert {:ok, connection} = Connection.start_link(opts)
    assert :ok = Connection.connect(connection, uri)
    assert :ok = Connection.send(connection, %Settings{})
    stream_id = StreamGen.next_stream_id(stream_gen)
    headers = %Headers{stream_id: stream_id,
      flags: %Headers.Flags{end_headers: true},
      payload: %Headers.Payload{hbf: [
        {":scheme", "https"},
        {":authority", authority},
        {":path", "/"},
        {":method", "GET"}
      ]}
    }
    assert :ok = Connection.send(connection, headers)
    receive do msg ->
      assert {:ankh, :headers, _, [_|_]} = msg
    end
    receive do msg ->
      assert {:ankh, :stream_data, _, _} = msg
    end
  end
end
