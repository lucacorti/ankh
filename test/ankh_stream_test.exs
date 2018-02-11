defmodule AnkhTest.Stream do
  use ExUnit.Case

  alias Ankh.Frame.{Data, Headers, Ping, Priority, RstStream, WindowUpdate}
  alias Ankh.Stream

  doctest Stream

  @stream_id 1

  setup_all do
    %{
      stream: Stream.new(:ankh_test_mock_connection, @stream_id)
    }
  end

  test "receiving frame on the wrong stream raises", ctx do
    frame = %Headers{stream_id: 3}

    assert_raise RuntimeError, "FATAL on stream 1: can't receive frame for stream 3", fn ->
      Stream.recv(ctx.stream, frame)
    end
  end

  test "stream idle to open on receiving headers", ctx do
    assert {:ok, stream} =
             ctx.stream
             |> Stream.recv(%Headers{stream_id: @stream_id})

    assert stream.state === :open
  end

  test "stream idle protocol_error on receiving frame != HEADERS", ctx do
    assert {:error, :protocol_error} =
             ctx.stream
             |> Stream.recv(%Ping{stream_id: @stream_id})
  end

  test "stream idle to open on sending headers", ctx do
    assert {:ok, stream} =
             ctx.stream
             |> Stream.send(%Headers{stream_id: @stream_id})

    assert stream.state === :open
  end

  test "stream reserved_local to half_closed_remote on sending headers", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_local}
      |> Stream.send(%Headers{stream_id: @stream_id})

    assert stream.state === :half_closed_remote
  end

  test "stream reserved_local to closed on sending rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_local}
      |> Stream.send(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream reserved_local to closed on receiving rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_local}
      |> Stream.recv(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream reserved_local can send priority", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_local}
      |> Stream.send(%Priority{stream_id: @stream_id})

    assert stream.state === :reserved_local
  end

  test "stream reserved_local can receive priority", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_local}
      |> Stream.recv(%Priority{stream_id: @stream_id})

    assert stream.state === :reserved_local
  end

  test "stream reserved_local can receive window_update", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_local}
      |> Stream.recv(%WindowUpdate{stream_id: @stream_id})

    assert stream.state === :reserved_local
  end

  test "stream reserved_local protocol_error on other frame type", ctx do
    stream =
      %{ctx.stream | state: :reserved_local}
      |> Stream.recv(%Ping{stream_id: @stream_id})

    assert stream === {:error, :protocol_error}
  end

  test "stream reserved_remote to half_closed_remote on receiving headers", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_remote}
      |> Stream.recv(%Headers{stream_id: @stream_id})

    assert stream.state === :half_closed_local
  end

  test "stream reserved_remote to closed on sending rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_remote}
      |> Stream.send(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream reserved_remote to closed on receiving rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_remote}
      |> Stream.recv(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream reserved_remote can send priority", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_remote}
      |> Stream.send(%Priority{stream_id: @stream_id})

    assert stream.state === :reserved_remote
  end

  test "stream reserved_remote can receive priority", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :reserved_remote}
      |> Stream.recv(%Priority{stream_id: @stream_id})

    assert stream.state === :reserved_remote
  end

  test "stream reserved_remote protocol_error on other frame type", ctx do
    {:error, :protocol_error} =
      %{ctx.stream | state: :reserved_remote}
      |> Stream.recv(%Ping{stream_id: @stream_id})
  end

  test "stream open can receive and send any frame type", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :open}
      |> Stream.recv(%Data{stream_id: @stream_id})

    assert stream.state === :open
  end

  test "stream open to half_closed_remote on receiving flag END_STREAM", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :open}
      |> Stream.recv(%Headers{stream_id: @stream_id, flags: %Headers.Flags{end_stream: true}})

    assert stream.state === :half_closed_remote
  end

  test "stream open to half_closed_local on sending flag END_STREAM", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :open}
      |> Stream.send(%Headers{stream_id: @stream_id, flags: %Headers.Flags{end_stream: true}})

    assert stream.state === :half_closed_local
  end

  test "stream open to closed on sending rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :open}
      |> Stream.send(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream open to closed on receiving rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :open}
      |> Stream.send(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream half_closed_local can send window_update", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_local}
      |> Stream.send(%WindowUpdate{stream_id: @stream_id})

    assert stream.state === :half_closed_local
  end

  test "stream half_closed_local can send priority", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_local}
      |> Stream.send(%Priority{stream_id: @stream_id})

    assert stream.state === :half_closed_local
  end

  test "stream half_closed_local to closed on sending rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_local}
      |> Stream.send(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream half_closed_local to closed on receiving flag END_STREAM", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_local}
      |> Stream.recv(%Headers{stream_id: @stream_id, flags: %Headers.Flags{end_stream: true}})

    assert stream.state === :closed
  end

  test "stream half_closed_local to closed on receiving rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_local}
      |> Stream.recv(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream half_closed_remote can receive window_update", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_remote}
      |> Stream.recv(%WindowUpdate{stream_id: @stream_id})

    assert stream.state === :half_closed_remote
  end

  test "stream half_closed_remote can receive priority", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_remote}
      |> Stream.recv(%Priority{stream_id: @stream_id})

    assert stream.state === :half_closed_remote
  end

  test "stream half_closed_remote error stream_closed on other frame types", ctx do
    assert {:error, :stream_closed} ===
             %{ctx.stream | state: :half_closed_remote}
             |> Stream.recv(%Headers{stream_id: @stream_id})
  end

  test "stream half_closed_remote can send frame type", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_remote}
      |> Stream.send(%Headers{stream_id: @stream_id})

    assert stream.state === :half_closed_remote
  end

  test "stream half_closed_remote to closed on sending rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_remote}
      |> Stream.send(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream half_closed_remote to closed on sending flag END_STREAM", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_remote}
      |> Stream.send(%Headers{stream_id: @stream_id, flags: %Headers.Flags{end_stream: true}})

    assert stream.state === :closed
  end

  test "stream half_closed_remote to closed on receiving rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :half_closed_remote}
      |> Stream.recv(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream closed can send priority", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :closed}
      |> Stream.send(%Priority{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream closed can receive window_update", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :closed}
      |> Stream.recv(%WindowUpdate{stream_id: @stream_id})

    assert stream.state === :closed
  end

  test "stream closed can receive rst_stream", ctx do
    {:ok, stream} =
      %{ctx.stream | state: :closed}
      |> Stream.recv(%RstStream{stream_id: @stream_id})

    assert stream.state === :closed
  end
end
