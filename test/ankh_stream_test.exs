defmodule AnkhTest.Stream do
  use ExUnit.Case, async: true

  alias Ankh.Frame.{Data, Headers, Ping, Priority, RstStream, Settings, WindowUpdate}
  alias Ankh.Stream
  alias HPack.Table

  doctest Stream

  @stream_id 1

  setup do
    %{
      header_table_size: header_table_size,
      max_frame_size: max_frame_size
    } = %Settings.Payload{}

    {:ok, recv_table} = Table.start_link(header_table_size)
    {:ok, send_table} = Table.start_link(header_table_size)

    {:ok, stream} =
      Stream.start_link(
        Ankh.Connection.Mock,
        @stream_id,
        recv_table,
        send_table,
        max_frame_size,
        self()
      )

    %{stream: stream}
  end

  test "receiving frame on the wrong stream raises", %{stream: stream} do
    assert {:error, :stream_id_mismatch} ==
             stream
             |> Stream.recv(%Headers{stream_id: 3})
  end

  test "stream idle to open on receiving headers", %{stream: stream} do
    assert {:ok, :open} ==
             stream
             |> Stream.recv(%Headers{stream_id: @stream_id})
  end

  test "stream idle protocol_error on receiving frame != HEADERS", %{stream: stream} do
    assert {:error, :protocol_error} ==
             stream
             |> Stream.recv(%Ping{stream_id: @stream_id})
  end

  test "stream idle to open on sending headers", %{stream: stream} do
    assert {:ok, :open} ==
             stream
             |> Stream.send(%Headers{flags: %Headers.Flags{end_headers: true}})
  end

  test "stream reserved_local to half_closed_remote on sending headers", %{stream: stream} do
    assert {:ok, :reserved_local} ==
             stream
             |> Stream.reserve(:local)

    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.send(%Headers{})
  end

  test "stream reserved_local to closed on sending rst_stream", %{stream: stream} do
    assert {:ok, :reserved_local} ==
             stream
             |> Stream.reserve(:local)

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%RstStream{})
  end

  test "stream reserved_local to closed on receiving rst_stream", %{stream: stream} do
    assert {:ok, :reserved_local} ==
             stream
             |> Stream.reserve(:local)

    assert {:ok, :closed} ==
             stream
             |> Stream.recv(%RstStream{stream_id: @stream_id})
  end

  test "stream reserved_local can send priority", %{stream: stream} do
    assert {:ok, :reserved_local} ==
             stream
             |> Stream.reserve(:local)

    assert {:ok, :reserved_local} ==
             stream
             |> Stream.send(%Priority{})
  end

  test "stream reserved_local can receive priority", %{stream: stream} do
    assert {:ok, :reserved_local} ==
             stream
             |> Stream.reserve(:local)

    assert {:ok, :reserved_local} ==
             stream
             |> Stream.recv(%Priority{stream_id: @stream_id})
  end

  test "stream reserved_local can receive window_update", %{stream: stream} do
    assert {:ok, :reserved_local} ==
             stream
             |> Stream.reserve(:local)

    assert {:ok, :reserved_local} ==
             stream
             |> Stream.recv(%WindowUpdate{stream_id: @stream_id})
  end

  test "stream reserved_local protocol_error on other frame type", %{stream: stream} do
    assert {:ok, :reserved_local} ==
             stream
             |> Stream.reserve(:local)

    assert {:error, :protocol_error} ==
             stream
             |> Stream.recv(%Ping{stream_id: @stream_id})
  end

  test "stream reserved_remote to half_closed_remote on receiving headers", %{stream: stream} do
    assert {:ok, :reserved_remote} ==
             stream
             |> Stream.reserve(:remote)

    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.recv(%Headers{stream_id: @stream_id})
  end

  test "stream reserved_remote to closed on sending rst_stream", %{stream: stream} do
    assert {:ok, :reserved_remote} ==
             stream
             |> Stream.reserve(:remote)

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%RstStream{})
  end

  test "stream reserved_remote to closed on receiving rst_stream", %{stream: stream} do
    assert {:ok, :reserved_remote} ==
             stream
             |> Stream.reserve(:remote)

    assert {:ok, :closed} ==
             stream
             |> Stream.recv(%RstStream{stream_id: @stream_id})
  end

  test "stream reserved_remote can send priority", %{stream: stream} do
    assert {:ok, :reserved_remote} ==
             stream
             |> Stream.reserve(:remote)

    assert {:ok, :reserved_remote} ==
             stream
             |> Stream.send(%Priority{})
  end

  test "stream reserved_remote can receive priority", %{stream: stream} do
    assert {:ok, :reserved_remote} ==
             stream
             |> Stream.reserve(:remote)

    assert {:ok, :reserved_remote} ==
             stream
             |> Stream.recv(%Priority{stream_id: @stream_id})
  end

  test "stream reserved_remote protocol_error on other frame type", %{stream: stream} do
    assert {:ok, :reserved_remote} ==
             stream
             |> Stream.reserve(:remote)

    assert {:error, :protocol_error} ==
             stream
             |> Stream.recv(%Ping{stream_id: @stream_id})
  end

  test "stream open can receive and send any frame type", %{stream: stream} do
    assert {:ok, :open} ==
             stream
             |> Stream.send(%Headers{flags: %Headers.Flags{end_headers: true}})

    assert {:ok, :open} ==
             stream
             |> Stream.recv(%Data{stream_id: @stream_id})
  end

  test "stream open to half_closed_remote on receiving flag END_STREAM", %{stream: stream} do
    assert {:ok, :open} ==
             stream
             |> Stream.send(%Headers{})

    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })
  end

  test "stream open to half_closed_local on sending flag END_STREAM", %{stream: stream} do
    assert {:ok, :open} ==
             stream
             |> Stream.send(%Headers{})

    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%Headers{
               flags: %Headers.Flags{end_stream: true}
             })
  end

  test "stream open to closed on sending rst_stream", %{stream: stream} do
    assert {:ok, :open} ==
             stream
             |> Stream.send(%Headers{})

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%RstStream{})
  end

  test "stream open to closed on receiving rst_stream", %{stream: stream} do
    assert {:ok, :open} ==
             stream
             |> Stream.send(%Headers{})

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%RstStream{})
  end

  test "stream half_closed_local can send window_update", %{stream: stream} do
    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%Headers{
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%WindowUpdate{})
  end

  test "stream half_closed_local can send priority", %{stream: stream} do
    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%Headers{
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%Priority{})
  end

  test "stream half_closed_local to closed on sending rst_stream", %{stream: stream} do
    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%Headers{
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%RstStream{})
  end

  test "stream half_closed_local to closed on receiving flag END_STREAM", %{stream: stream} do
    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%Headers{
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })
  end

  test "stream half_closed_local to closed on receiving rst_stream", %{stream: stream} do
    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%Headers{
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.recv(%RstStream{stream_id: @stream_id})
  end

  test "stream half_closed_remote can receive window_update", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%WindowUpdate{stream_id: @stream_id})
  end

  test "stream half_closed_remote can receive priority", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Priority{stream_id: @stream_id})
  end

  test "stream half_closed_remote error stream_closed on other frame types", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:error, :stream_closed} ==
             stream
             |> Stream.recv(%Headers{stream_id: @stream_id})
  end

  test "stream half_closed_remote can send any frame type", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.send(%Headers{})
  end

  test "stream half_closed_remote to closed on sending rst_stream", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%RstStream{})
  end

  test "stream half_closed_remote to closed on sending flag END_STREAM", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%Headers{flags: %Headers.Flags{end_stream: true}})
  end

  test "stream half_closed_remote to closed on receiving rst_stream", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.recv(%RstStream{stream_id: @stream_id})
  end

  test "stream closed can send priority", %{stream: stream} do
    assert {:ok, :half_closed_local} ==
             stream
             |> Stream.send(%Headers{flags: %Headers.Flags{end_stream: true}})

    assert {:ok, :closed} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%Priority{})
  end

  test "stream closed can receive window_update", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%Headers{
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.recv(%WindowUpdate{stream_id: @stream_id})
  end

  test "stream closed can receive rst_stream", %{stream: stream} do
    assert {:ok, :half_closed_remote} ==
             stream
             |> Stream.recv(%Headers{
               stream_id: @stream_id,
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.send(%Headers{
               flags: %Headers.Flags{end_stream: true}
             })

    assert {:ok, :closed} ==
             stream
             |> Stream.recv(%RstStream{stream_id: @stream_id})
  end
end
