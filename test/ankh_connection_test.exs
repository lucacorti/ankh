defmodule AnkhTest.Connection do
  use ExUnit.Case

  alias HPack
  alias HPack.Table

  alias Ankh.{Connection, Frame}
  alias Frame.{Data, Headers, Settings, WindowUpdate}

  alias AnkhTest.StreamGen

  @hostname "https://www.google.it"

  doctest Connection

  setup do
    uri = URI.parse(@hostname)
    {:ok, stream_gen} = StreamGen.start_link(:client)
    {:ok, send_table} = Table.start_link(4_096)
    {:ok, [uri: uri, send_table: send_table, stream_gen: stream_gen]}
  end

  test "get request", %{
    uri: %URI{authority: authority} = uri,
    stream_gen: stream_gen,
    send_table: table
  } do
    assert {:ok, pid} = Connection.start_link(uri: uri)
    assert :ok = Connection.connect(pid)
    assert :ok = Connection.send(pid, %Settings{})
    stream_id = StreamGen.next_stream_id(stream_gen)

    hbf =
      HPack.encode(
        [
          {":scheme", "https"},
          {":authority", authority},
          {":path", "/"},
          {":method", "GET"}
        ],
        table
      )

    headers = %Headers{
      stream_id: stream_id,
      flags: %Headers.Flags{end_headers: true},
      payload: %Headers.Payload{hbf: hbf}
    }

    assert :ok = Connection.send(pid, headers)

    receive do
      msg ->
        assert {:ankh, :frame, %Settings{}} = msg
    end

    receive do
      msg ->
        assert {:ankh, :frame, %WindowUpdate{}} = msg
    end

    receive do
      msg ->
        assert {:ankh, :frame, %Settings{flags: %{ack: true}}} = msg
    end

    receive do
      msg ->
        assert {:ankh, :frame, %Headers{}} = msg
    end

    receive do
      msg ->
        assert {:ankh, :frame, %Data{}} = msg
    end
  end
end
