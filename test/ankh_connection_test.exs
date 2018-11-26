defmodule AnkhTest.Connection do
  use ExUnit.Case

  alias HPack
  alias HPack.Table

  alias Ankh.{Connection, Frame, Stream}
  alias Frame.{Data, Headers, Settings, WindowUpdate}

  alias AnkhTest.StreamGen

  @hostname "https://www.google.com"

  doctest Connection

  setup do
    uri = URI.parse(@hostname)
    {:ok, stream_gen} = StreamGen.start_link(:client)
    %{header_table_size: header_table_size} = %Settings.Payload{}
    {:ok, send_table} = Table.start_link(header_table_size)
    {:ok, [uri: uri, send_table: send_table, stream_gen: stream_gen]}
  end

  test "get request", %{
    uri: %URI{authority: authority} = uri,
    stream_gen: stream_gen,
    send_table: send_table
  } do
    assert {:ok, pid} = Connection.start_link(uri: uri)
    assert :ok = Connection.connect(pid)

    assert_receive {:ankh, :frame,
                    %Settings{
                      flags: %{ack: false},
                      payload: %{
                        max_frame_size: max_frame_size
                      }
                    } = settings}

    :ok =
      Connection.send(pid, %Settings{
        settings
        | flags: %Settings.Flags{ack: true},
          payload: nil,
          length: 0
      })

    assert :ok = Connection.send(pid, %Settings{})
    assert_receive {:ankh, :frame, %Settings{flags: %{ack: true}}}
    assert_receive {:ankh, :frame, %WindowUpdate{}}

    stream_id = StreamGen.next_stream_id(stream_gen)
    assert {:ok, _} = Stream.start_link(pid, stream_id, send_table, self(), :reassemble)

    headers =
      %Headers{
        stream_id: stream_id,
        flags: %Headers.Flags{end_headers: true},
        payload: %Headers.Payload{
          hbf:
            [{":scheme", "https"}, {":authority", authority}, {":path", "/"}, {":method", "GET"}]
            |> HPack.encode(send_table)
        }
      }
      |> Frame.split(max_frame_size)

    for frame <- headers do
      assert {:ok, state} =
               Stream.send({:via, Registry, {Ankh.Stream.Registry, {pid, stream_id}}}, frame)
    end

    receive_headers()
    receive_data()
  end

  def receive_headers do
    assert_receive {:ankh, :frame, %Headers{flags: %{end_headers: eh}}}, 1_000

    unless eh do
      receive_headers()
    end
  end

  def receive_data do
    assert_receive {:ankh, :frame, %Data{flags: %{end_stream: es}}}, 1_000

    unless es do
      receive_data()
    end
  end
end
