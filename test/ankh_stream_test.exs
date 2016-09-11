defmodule AnkhTest.Stream do
  use ExUnit.Case
  alias Ankh.{Frame, Stream}

  doctest Stream

  @stream_id 1

  test "receiving frame on the wrong stream raises" do
    frame = %Frame{stream_id: 3, type: :headers}
    assert_raise RuntimeError,
    "FATAL on stream 1: this frame has stream id 3!",
    fn ->
      Stream.received_frame(%Stream{id: @stream_id}, frame)
    end
  end

  test "stream idle to open on receiving headers" do
    stream = %Stream{id: @stream_id}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :headers})

    assert stream === {:ok, %Stream{id: @stream_id, state: :open}}
  end

  test "stream idle protocol_error on receiving frame != HEADERS" do
    stream =  %Stream{id: @stream_id}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :ping})

    assert stream === {:error, :protocol_error}
  end

  test "stream idle to open on sending headers" do
    stream =  %Stream{id: @stream_id}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :headers})

    assert stream === {:ok, %Stream{id: @stream_id, state: :open}}
  end

  test "stream reserved_local to half_closed_remote on sending headers" do
    stream = %Stream{id: @stream_id, state: :reserved_local}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :headers})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_remote}}
  end

  test "stream reserved_local to closed on sending rst_stream" do
    stream = %Stream{id: @stream_id, state: :reserved_local}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream reserved_local to closed on receiving rst_stream" do
    stream = %Stream{id: @stream_id, state: :reserved_local}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream reserved_local can send priority" do
    stream = %Stream{id: @stream_id, state: :reserved_local}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :priority})

    assert stream === {:ok, %Stream{id: @stream_id, state: :reserved_local}}
  end

  test "stream reserved_local can receive priority" do
    stream = %Stream{id: @stream_id, state: :reserved_local}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :priority})

    assert stream === {:ok, %Stream{id: @stream_id, state: :reserved_local}}
  end

  test "stream reserved_local can receive window_update" do
    stream = %Stream{id: @stream_id, state: :reserved_local}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :window_update})

    assert stream === {:ok, %Stream{id: @stream_id, state: :reserved_local}}
  end

  test "stream reserved_local protocol_error on other frame type" do
    stream =  %Stream{id: @stream_id, state: :reserved_local}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :ping})

    assert stream === {:error, :protocol_error}
  end

  test "stream reserved_remote to half_closed_remote on receiving headers" do
    stream = %Stream{id: @stream_id, state: :reserved_remote}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :headers})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_local}}
  end

  test "stream reserved_remote to closed on sending rst_stream" do
    stream = %Stream{id: @stream_id, state: :reserved_remote}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream reserved_remote to closed on receiving rst_stream" do
    stream = %Stream{id: @stream_id, state: :reserved_remote}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream reserved_remote can send priority" do
    stream = %Stream{id: @stream_id, state: :reserved_remote}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :priority})

    assert stream === {:ok, %Stream{id: @stream_id, state: :reserved_remote}}
  end

  test "stream reserved_remote can receive priority" do
    stream = %Stream{id: @stream_id, state: :reserved_remote}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :priority})

    assert stream === {:ok, %Stream{id: @stream_id, state: :reserved_remote}}
  end

  test "stream reserved_remote protocol_error on other frame type" do
    stream =  %Stream{id: @stream_id, state: :reserved_remote}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :ping})

    assert stream === {:error, :protocol_error}
  end

  test "stream open can receive and send any frame type" do
    stream =  %Stream{id: @stream_id, state: :open}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :data})

    assert stream === {:ok, %Stream{id: @stream_id, state: :open}}
  end

  test "stream open to half_closed_remote on receiving flag END_STREAM" do
    stream =  %Stream{id: @stream_id, state: :open}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :headers,
       flags: %Frame.Headers.Flags{end_stream: true}})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_remote}}
  end

  test "stream open to half_closed_local on sending flag END_STREAM" do
    stream =  %Stream{id: @stream_id, state: :open}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :headers,
       flags: %Frame.Headers.Flags{end_stream: true}})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_local}}
  end

  test "stream open to closed on sending rst_stream" do
    stream = %Stream{id: @stream_id, state: :open}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream open to closed on receiving rst_stream" do
    stream = %Stream{id: @stream_id, state: :open}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream half_closed_local can send window_update" do
    stream = %Stream{id: @stream_id, state: :half_closed_local}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :window_update})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_local}}
  end

  test "stream half_closed_local can send priority" do
    stream = %Stream{id: @stream_id, state: :half_closed_local}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :priority})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_local}}
  end

  test "stream half_closed_local to closed on sending rst_stream" do
    stream = %Stream{id: @stream_id, state: :half_closed_local}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream half_closed_local to closed on receiving flag END_STREAM" do
    stream =  %Stream{id: @stream_id, state: :half_closed_local}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :headers,
       flags: %Frame.Headers.Flags{end_stream: true}})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream half_closed_local to closed on receiving rst_stream" do
    stream = %Stream{id: @stream_id, state: :half_closed_local}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream half_closed_remote can receive window_update" do
    stream = %Stream{id: @stream_id, state: :half_closed_remote}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :window_update})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_remote}}
  end

  test "stream half_closed_remote can receive priority" do
    stream = %Stream{id: @stream_id, state: :half_closed_remote}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :priority})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_remote}}
  end

  test "stream half_closed_remote error stream_closed on other frame types" do
    stream = %Stream{id: @stream_id, state: :half_closed_remote}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :headers})

    assert stream === {:error, :stream_closed}
  end

  test "stream half_closed_remote can send frame type" do
    stream = %Stream{id: @stream_id, state: :half_closed_remote}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :headers})

    assert stream === {:ok, %Stream{id: @stream_id, state: :half_closed_remote}}
  end

  test "stream half_closed_remote to closed on sending rst_stream" do
    stream = %Stream{id: @stream_id, state: :half_closed_remote}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream half_closed_remote to closed on sending flag END_STREAM" do
    stream =  %Stream{id: @stream_id, state: :half_closed_remote}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :headers,
       flags: %Frame.Headers.Flags{end_stream: true}})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream half_closed_remote to closed on receiving rst_stream" do
    stream = %Stream{id: @stream_id, state: :half_closed_remote}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream closed can send priority" do
    stream = %Stream{id: @stream_id, state: :closed}
    |> Stream.send_frame(%Frame{stream_id: @stream_id, type: :priority})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream closed can receive window_update" do
    stream = %Stream{id: @stream_id, state: :closed}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :window_update})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end

  test "stream closed can receive rst_stream" do
    stream = %Stream{id: @stream_id, state: :closed}
    |> Stream.received_frame(%Frame{stream_id: @stream_id, type: :rst_stream})

    assert stream === {:ok, %Stream{id: @stream_id, state: :closed}}
  end
end
