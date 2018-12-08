defmodule AnkhTest.Connection do
  use ExUnit.Case, async: true

  alias Ankh.{Connection, Frame, Stream}
  alias Frame.Headers

  @address "https://www.google.com"

  doctest Connection

  setup do
    uri = URI.parse(@address)
    {:ok, [uri: uri]}
  end

  test "get request", %{
    uri: %URI{authority: authority} = uri
  } do
    assert {:ok, connection} = Connection.start_link(uri: uri)
    assert :ok = Connection.connect(connection)
    assert {:ok, stream_id, stream} = Connection.start_stream(connection)

    headers = %Headers{
      flags: %Headers.Flags{end_headers: true},
      payload: %Headers.Payload{
        hbf: [{":scheme", "https"}, {":authority", authority}, {":path", "/"}, {":method", "GET"}]
      }
    }

    assert {:ok, state} = Stream.send(stream, headers)

    receive_headers(stream_id)
    receive_data(stream_id)
    receive_closed(stream_id)
  end

  defp receive_headers(stream_id) do
    assert_receive {:ankh, :headers, ^stream_id, _headers}, 1_000
  end

  defp receive_data(stream_id) do
    assert_receive {:ankh, :data, ^stream_id, _data, end_stream}, 1_000

    unless end_stream do
      receive_data(stream_id)
    end
  end

  defp receive_closed(stream_id) do
    assert_receive {:ankh, :stream, ^stream_id, :closed}, 1_000
  end
end
