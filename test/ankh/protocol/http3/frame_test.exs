defmodule Ankh.Protocol.HTTP3.FrameTest do
  use ExUnit.Case, async: true

  import Bitwise

  doctest Ankh.Protocol.HTTP3.Frame

  alias Ankh.Protocol.HTTP3.Frame

  alias Ankh.Protocol.HTTP3.Frame.{
    CancelPush,
    Data,
    GoAway,
    Headers,
    MaxPushId,
    PushPromise,
    Settings
  }

  # ---------------------------------------------------------------------------
  # VLI encoding
  # ---------------------------------------------------------------------------

  describe "encode_vli/1" do
    test "encodes zero as a single byte" do
      assert Frame.encode_vli(0) == <<0x00>>
    end

    test "encodes the 1-byte boundary value 63" do
      assert Frame.encode_vli(63) == <<63>>
    end

    test "encodes 64 in two bytes with 01 prefix" do
      <<msb, _>> = Frame.encode_vli(64)
      assert msb >>> 6 == 1
    end

    test "encodes 16_383 in two bytes" do
      encoded = Frame.encode_vli(16_383)
      assert byte_size(encoded) == 2
      assert {:ok, 16_383, <<>>} = Frame.decode_vli(encoded)
    end

    test "encodes 16_384 in four bytes with 10 prefix" do
      encoded = Frame.encode_vli(16_384)
      assert byte_size(encoded) == 4
      <<msb, _::binary>> = encoded
      assert msb >>> 6 == 2
    end

    test "encodes 1_073_741_823 in four bytes" do
      encoded = Frame.encode_vli(1_073_741_823)
      assert byte_size(encoded) == 4
      assert {:ok, 1_073_741_823, <<>>} = Frame.decode_vli(encoded)
    end

    test "encodes 1_073_741_824 in eight bytes with 11 prefix" do
      encoded = Frame.encode_vli(1_073_741_824)
      assert byte_size(encoded) == 8
      <<msb, _::binary>> = encoded
      assert msb >>> 6 == 3
    end

    test "round-trips a large 8-byte value" do
      n = 4_611_686_018_427_387_903
      encoded = Frame.encode_vli(n)
      assert byte_size(encoded) == 8
      assert {:ok, ^n, <<>>} = Frame.decode_vli(encoded)
    end

    test "always uses the smallest encoding" do
      assert byte_size(Frame.encode_vli(0)) == 1
      assert byte_size(Frame.encode_vli(63)) == 1
      assert byte_size(Frame.encode_vli(64)) == 2
      assert byte_size(Frame.encode_vli(16_383)) == 2
      assert byte_size(Frame.encode_vli(16_384)) == 4
      assert byte_size(Frame.encode_vli(1_073_741_823)) == 4
      assert byte_size(Frame.encode_vli(1_073_741_824)) == 8
    end
  end

  # ---------------------------------------------------------------------------
  # VLI decoding
  # ---------------------------------------------------------------------------

  describe "decode_vli/1" do
    test "decodes a 1-byte integer" do
      assert {:ok, 7, <<>>} = Frame.decode_vli(<<7>>)
    end

    test "decodes zero" do
      assert {:ok, 0, <<>>} = Frame.decode_vli(<<0>>)
    end

    test "decodes 63 (max 1-byte)" do
      assert {:ok, 63, <<>>} = Frame.decode_vli(<<63>>)
    end

    test "decodes a 2-byte integer and returns remainder" do
      assert {:ok, 494, "rest"} = Frame.decode_vli(<<0x41, 0xEE, "rest">>)
    end

    test "decodes a 4-byte integer" do
      encoded = Frame.encode_vli(100_000)
      assert {:ok, 100_000, <<>>} = Frame.decode_vli(encoded)
    end

    test "decodes an 8-byte integer" do
      encoded = Frame.encode_vli(2_000_000_000_000)
      assert {:ok, 2_000_000_000_000, <<>>} = Frame.decode_vli(encoded)
    end

    test "returns :incomplete for empty binary" do
      assert {:error, :incomplete} = Frame.decode_vli(<<>>)
    end

    test "returns :incomplete when 2-byte integer is truncated" do
      assert {:error, :incomplete} = Frame.decode_vli(<<0x40>>)
    end

    test "returns :incomplete when 4-byte integer is truncated" do
      assert {:error, :incomplete} = Frame.decode_vli(<<0x80, 0x00, 0x00>>)
    end

    test "returns :incomplete when 8-byte integer is truncated" do
      assert {:error, :incomplete} = Frame.decode_vli(<<0xC0, 0x00, 0x00>>)
    end

    test "round-trips all boundary values" do
      for n <- [0, 63, 64, 16_383, 16_384, 1_073_741_823, 1_073_741_824] do
        encoded = Frame.encode_vli(n)

        assert {:ok, ^n, <<>>} = Frame.decode_vli(encoded),
               "round-trip failed for #{n}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Frame encoding — struct-based API
  # ---------------------------------------------------------------------------

  describe "encode/1" do
    test "encodes a DATA frame" do
      frame = %Data{payload: %Data.Payload{data: "hello"}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      assert IO.iodata_to_binary(iodata) == <<0x00, 0x05, "hello">>
      assert updated.length == 5
      assert updated.type == 0x0
    end

    test "encodes a HEADERS frame" do
      frame = %Headers{payload: %Headers.Payload{hbf: "hdr"}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      assert IO.iodata_to_binary(iodata) == <<0x01, 0x03, "hdr">>
      assert updated.length == 3
      assert updated.type == 0x1
    end

    test "encodes a SETTINGS frame with [{1, 0}, {7, 0}]" do
      frame = %Settings{payload: %Settings.Payload{settings: [{1, 0}, {7, 0}]}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      assert IO.iodata_to_binary(iodata) == <<0x04, 0x04, 0x01, 0x00, 0x07, 0x00>>
      assert updated.length == 4
      assert updated.type == 0x4
    end

    test "encodes a SETTINGS frame with empty settings" do
      frame = %Settings{payload: %Settings.Payload{settings: []}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      assert IO.iodata_to_binary(iodata) == <<0x04, 0x00>>
      assert updated.length == 0
    end

    test "encodes a CANCEL_PUSH frame with push_id: 42" do
      frame = %CancelPush{payload: %CancelPush.Payload{push_id: 42}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      bin = IO.iodata_to_binary(iodata)
      # type 0x03, VLI length, VLI push_id
      assert <<0x03, _len, _push_id_vli::binary>> = bin
      # push_id 42 < 64 so encodes as 1 byte
      assert updated.length == byte_size(Frame.encode_vli(42))
      assert updated.type == 0x3
    end

    test "encodes a GOAWAY frame with stream_id: 42" do
      frame = %GoAway{payload: %GoAway.Payload{stream_id: 42}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      bin = IO.iodata_to_binary(iodata)
      assert <<0x07, _len, _stream_id_vli::binary>> = bin
      assert updated.length == byte_size(Frame.encode_vli(42))
      assert updated.type == 0x7
    end

    test "encodes a MAX_PUSH_ID frame with push_id: 100" do
      frame = %MaxPushId{payload: %MaxPushId.Payload{push_id: 100}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      bin = IO.iodata_to_binary(iodata)
      assert <<0x0D, _len, _push_id_vli::binary>> = bin
      # push_id 100 >= 64 so encodes as 2 bytes
      assert updated.length == byte_size(Frame.encode_vli(100))
      assert updated.type == 0xD
    end

    test "encodes a PUSH_PROMISE frame with push_id: 1, hbf: \"hdr\"" do
      frame = %PushPromise{payload: %PushPromise.Payload{push_id: 1, hbf: "hdr"}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      bin = IO.iodata_to_binary(iodata)
      # type 0x05, length VLI, then push_id=1 as 1-byte VLI (0x01), then hbf bytes
      assert <<0x05, _len, 0x01, "hdr">> = bin
      # payload = 1-byte push_id VLI + 3-byte hbf
      assert updated.length == 4
      assert updated.type == 0x5
    end

    test "encodes an empty DATA frame" do
      frame = %Data{payload: %Data.Payload{data: <<>>}}
      assert {:ok, updated, iodata} = Frame.encode(frame)
      assert IO.iodata_to_binary(iodata) == <<0x00, 0x00>>
      assert updated.length == 0
    end

    test "sets updated_frame.length to the payload byte count" do
      frame = %Data{payload: %Data.Payload{data: "hello world"}}
      assert {:ok, updated, _iodata} = Frame.encode(frame)
      assert updated.length == 11
    end

    test "preserves the integer type code in updated_frame" do
      frame = %Headers{payload: %Headers.Payload{hbf: "x"}}
      assert {:ok, updated, _iodata} = Frame.encode(frame)
      assert updated.type == 0x1
    end
  end

  # ---------------------------------------------------------------------------
  # Streaming — Frame.stream/1
  #
  # stream/1 uses Stream.unfold/2.  After emitting {data, nil} for a partial
  # frame the next accumulator state is `data` (unchanged), which would loop
  # forever if the caller kept consuming.  Therefore:
  #   • tests involving partial frames use Enum.take/2 to stop early.
  #   • tests where every byte belongs to a complete frame use Enum.to_list/1
  #     (safe because the last next-state is <<>>, which terminates the stream).
  # ---------------------------------------------------------------------------

  describe "stream/1" do
    test "yields a complete DATA frame token" do
      {:ok, _, iodata} = Frame.encode(%Data{payload: %Data.Payload{data: "hi"}})
      bin = IO.iodata_to_binary(iodata)
      assert Frame.stream(bin) |> Enum.to_list() == [{"", {0, "hi"}}]
    end

    test "yields a complete HEADERS frame token" do
      {:ok, _, iodata} = Frame.encode(%Headers{payload: %Headers.Payload{hbf: "hdr"}})
      bin = IO.iodata_to_binary(iodata)
      assert Frame.stream(bin) |> Enum.to_list() == [{"", {1, "hdr"}}]
    end

    test "yields two consecutive frame tokens in order" do
      {:ok, _, d_io} = Frame.encode(%Data{payload: %Data.Payload{data: "hi"}})
      {:ok, _, h_io} = Frame.encode(%Headers{payload: %Headers.Payload{hbf: "hdr"}})
      bin = IO.iodata_to_binary([d_io, h_io])
      tokens = Frame.stream(bin) |> Enum.map(fn {_rest, t} -> t end)
      assert tokens == [{0, "hi"}, {1, "hdr"}]
    end

    test "yields nothing for an empty binary" do
      assert Frame.stream(<<>>) |> Enum.to_list() == []
    end

    test "yields {partial_bin, nil} for a partial frame" do
      # A DATA frame that claims 5 bytes of payload but only has 2.
      partial = <<0x00, 0x05, "ab">>
      # Use Enum.take/2 — Enum.to_list/1 would loop because the unfold keeps
      # returning the same partial buffer as the next accumulator state.
      result = Frame.stream(partial) |> Enum.take(1)
      assert [{^partial, nil}] = result
    end

    test "the rest field of a complete-frame token equals the unconsumed bytes" do
      {:ok, _, iodata} = Frame.encode(%Data{payload: %Data.Payload{data: "hi"}})
      leftover = "leftover"
      bin = IO.iodata_to_binary(iodata) <> leftover
      # Use Enum.take/2 because the leftover cannot be parsed as a valid frame
      # and would cause the unfold to loop.
      [{rest, {0, "hi"}}] = Frame.stream(bin) |> Enum.take(1)
      assert rest == leftover
    end

    test "carries the full payload for large frames (300 bytes)" do
      payload = :binary.copy(<<0xAB>>, 300)
      {:ok, _, iodata} = Frame.encode(%Data{payload: %Data.Payload{data: payload}})
      bin = IO.iodata_to_binary(iodata)
      # No leftover — Enum.to_list/1 is safe.
      [{_, {0, decoded_payload}}] = Frame.stream(bin) |> Enum.to_list()
      assert decoded_payload == payload
    end

    test "complete frame followed by partial yields two elements" do
      {:ok, _, iodata} = Frame.encode(%Data{payload: %Data.Payload{data: "hi"}})
      # A HEADERS frame that claims 5 bytes but only has 2.
      partial = <<0x01, 0x05, "ab">>
      bin = IO.iodata_to_binary(iodata) <> partial
      # Stop at 2 to avoid the infinite-loop behaviour on the partial tail.
      result = Frame.stream(bin) |> Enum.take(2)
      assert [{_, {0, "hi"}}, {^partial, nil}] = result
    end
  end

  # ---------------------------------------------------------------------------
  # Frame decoding — struct-based API
  # ---------------------------------------------------------------------------

  describe "decode/2" do
    test "decodes a DATA payload" do
      {:ok, decoded} = Frame.decode(%Data{}, "hello")
      assert decoded.payload.data == "hello"
      assert decoded.length == 5
    end

    test "decodes a HEADERS payload" do
      {:ok, decoded} = Frame.decode(%Headers{}, "hbf")
      assert decoded.payload.hbf == "hbf"
      assert decoded.length == 3
    end

    test "decodes a SETTINGS payload with [{1, 0}, {7, 0}]" do
      {:ok, decoded} = Frame.decode(%Settings{}, <<0x01, 0x00, 0x07, 0x00>>)
      assert decoded.payload.settings == [{1, 0}, {7, 0}]
      assert decoded.length == 4
    end

    test "decodes an empty SETTINGS payload" do
      {:ok, decoded} = Frame.decode(%Settings{}, <<>>)
      assert decoded.payload.settings == []
      assert decoded.length == 0
    end

    test "decodes a CANCEL_PUSH payload" do
      payload_bin = Frame.encode_vli(42)
      {:ok, decoded} = Frame.decode(%CancelPush{}, payload_bin)
      assert decoded.payload.push_id == 42
      assert decoded.length == byte_size(payload_bin)
    end

    test "decodes a GOAWAY payload" do
      payload_bin = Frame.encode_vli(99)
      {:ok, decoded} = Frame.decode(%GoAway{}, payload_bin)
      assert decoded.payload.stream_id == 99
      assert decoded.length == byte_size(payload_bin)
    end

    test "decodes a MAX_PUSH_ID payload" do
      payload_bin = Frame.encode_vli(7)
      {:ok, decoded} = Frame.decode(%MaxPushId{}, payload_bin)
      assert decoded.payload.push_id == 7
      assert decoded.length == byte_size(payload_bin)
    end

    test "decodes a PUSH_PROMISE payload" do
      # push_id=1 encoded as a 1-byte VLI (0x01), followed by the HBF bytes.
      payload = <<0x01, "hdr">>
      {:ok, decoded} = Frame.decode(%PushPromise{}, payload)
      assert decoded.payload.push_id == 1
      assert decoded.payload.hbf == "hdr"
      assert decoded.length == byte_size(payload)
    end

    test "sets decoded.length to byte_size(payload_binary) in every case" do
      payload = "some arbitrary data"
      {:ok, decoded} = Frame.decode(%Data{}, payload)
      assert decoded.length == byte_size(payload)
    end
  end

  # ---------------------------------------------------------------------------
  # Control-stream preface
  # ---------------------------------------------------------------------------

  describe "control_stream_preface/0" do
    test "is exactly 7 bytes long" do
      assert byte_size(Frame.control_stream_preface()) == 7
    end

    test "starts with the control stream type byte 0x00" do
      <<stream_type, _::binary>> = Frame.control_stream_preface()
      assert stream_type == 0x00
    end

    test "second byte is the SETTINGS frame type 0x04" do
      <<_, frame_type, _::binary>> = Frame.control_stream_preface()
      assert frame_type == 0x04
    end

    test "third byte is the payload length 4" do
      <<_, _, length, _::binary>> = Frame.control_stream_preface()
      assert length == 0x04
    end

    test "the embedded SETTINGS frame decodes with stream/1 and decode/2" do
      <<_stream_type, rest::binary>> = Frame.control_stream_preface()
      # rest is exactly one complete SETTINGS frame — Enum.to_list/1 is safe.
      [{_, {type_int, payload_bin}}] = Frame.stream(rest) |> Enum.to_list()
      assert type_int == 0x4
      {:ok, frame} = Frame.decode(%Settings{}, payload_bin)
      assert frame.payload.settings == [{1, 0}, {7, 0}]
    end

    test "payload decodes to QPACK_MAX_TABLE_CAPACITY=0 and QPACK_BLOCKED_STREAMS=0" do
      <<_, _, _, payload::binary>> = Frame.control_stream_preface()
      {:ok, frame} = Frame.decode(%Settings{}, payload)
      assert frame.payload.settings == [{1, 0}, {7, 0}]
    end
  end

  # ---------------------------------------------------------------------------
  # Encode / decode round-trips (struct → wire → struct)
  # ---------------------------------------------------------------------------

  describe "encode/decode round-trips" do
    test "round-trips a DATA frame" do
      struct = %Data{payload: %Data.Payload{data: "hello"}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%Data{}, payload_bin)
      assert decoded.payload.data == "hello"
    end

    test "round-trips a HEADERS frame" do
      struct = %Headers{payload: %Headers.Payload{hbf: "header bytes"}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%Headers{}, payload_bin)
      assert decoded.payload.hbf == "header bytes"
    end

    test "round-trips a SETTINGS frame" do
      settings = [{1, 0}, {6, 4096}, {7, 0}]
      struct = %Settings{payload: %Settings.Payload{settings: settings}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%Settings{}, payload_bin)
      assert decoded.payload.settings == settings
    end

    test "round-trips a CANCEL_PUSH frame" do
      struct = %CancelPush{payload: %CancelPush.Payload{push_id: 99}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%CancelPush{}, payload_bin)
      assert decoded.payload.push_id == 99
    end

    test "round-trips a GOAWAY frame" do
      struct = %GoAway{payload: %GoAway.Payload{stream_id: 7}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%GoAway{}, payload_bin)
      assert decoded.payload.stream_id == 7
    end

    test "round-trips a MAX_PUSH_ID frame" do
      struct = %MaxPushId{payload: %MaxPushId.Payload{push_id: 255}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%MaxPushId{}, payload_bin)
      assert decoded.payload.push_id == 255
    end

    test "round-trips a PUSH_PROMISE frame" do
      struct = %PushPromise{payload: %PushPromise.Payload{push_id: 3, hbf: "hbf bytes"}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%PushPromise{}, payload_bin)
      assert decoded.payload.push_id == 3
      assert decoded.payload.hbf == "hbf bytes"
    end

    test "round-trips a large DATA payload (70_000 bytes) — exercises multi-byte VLI length" do
      payload = :binary.copy("x", 70_000)
      struct = %Data{payload: %Data.Payload{data: payload}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%Data{}, payload_bin)
      assert decoded.payload.data == payload
    end

    test "round-trips an empty DATA payload" do
      struct = %Data{payload: %Data.Payload{data: <<>>}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%Data{}, payload_bin)
      assert decoded.payload.data == <<>>
    end

    test "round-trips SETTINGS with multiple pairs [{1, 0}, {6, 4096}, {7, 0}]" do
      settings = [{1, 0}, {6, 4096}, {7, 0}]
      struct = %Settings{payload: %Settings.Payload{settings: settings}}
      {:ok, _, iodata} = Frame.encode(struct)

      [{_, {type_int, payload_bin}}] =
        Frame.stream(IO.iodata_to_binary(iodata)) |> Enum.to_list()

      assert type_int == struct.type
      {:ok, decoded} = Frame.decode(%Settings{}, payload_bin)
      assert decoded.payload.settings == settings
    end
  end
end
