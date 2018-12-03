defmodule AnkhTest.Connection do
  use ExUnit.Case

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

    assert {:ok, stream} =
             Connection.start_stream(
               connection,
               :reassemble
             )

    headers = %Headers{
      flags: %Headers.Flags{end_headers: true},
      payload: %Headers.Payload{
        hbf: [{":scheme", "https"}, {":authority", authority}, {":path", "/"}, {":method", "GET"}]
      }
    }

    assert {:ok, state} = Stream.send(stream, headers)

    assert_receive {:ankh, :headers, _, _}, 1_000
    receive_data()

    assert :ok = Stream.close(stream)
    assert :ok = Connection.close(connection)
  end

  defp receive_data do
    assert_receive {:ankh, :data, _, _, end_stream}, 1_000

    unless end_stream do
      receive_data()
    end
  end
end
