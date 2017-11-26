defmodule Ankh.Stream do
  @moduledoc """
  HTTP/2 Stream strucure
  """

  alias Ankh.{Connection, Frame}
  alias Frame.{Data, Continuation, Error, Headers, Priority, PushPromise, RstStream, WindowUpdate}
  require Logger

  @typedoc """
  Stream states
  """
  @type state :: :idle | :open | :closed | :half_closed_local |
  :half_closed_remote | :reserved_remote | :reserved_local

  @type mode :: :reassemble | :streaming
  @typedoc """
  - id: stream id
  - state: stream state
  - mode: reassemble | :stream, request mode
  - hbf_type: :headers | :push_promise, type of HBF being accumulated
  - hbf: HBF accumulator, for reassembly
  - data: DATA accumulator, for reassembly
  - window_size: stream window size
  """
  @type t :: %__MODULE__{
    id: Integer.t,
    connection: Connection.t,
    state: state,
    mode: :reassemble | :streaming,
    recv_hbf_type: :headers | :push_promise,
    recv_hbf: iodata,
    recv_data: iodata,
    window_size: Integer.t
  }

  defstruct [
    id: 0,
    connection: nil,
    state: :idle,
    mode: :reassemble,
    recv_hbf_type: :headers,
    recv_hbf: [],
    recv_data: [],
    window_size: 2_147_483_647
  ]

  @typedoc """
  Stream Error
  """
  @type error :: {:error, Error.t}

  @doc """
  Creates a new Stream

  Parameters:
    - id: stream id
    - state: stream state
  """
  @spec new(Connection.t, Integer.t, mode) :: t
  def new(connection, id, mode \\ :reassemble) do
    %__MODULE__{connection: connection, id: id, mode: mode}
  end

  @doc """
  Process the reception of a frame through the Stream state machine
  """
  @spec recv(t, Frame.t) :: {:ok, t} | error

  def recv(%{id: id}, %{stream_id: stream_id}) when stream_id !== id do
    raise "FATAL on stream #{id}: can't receive frame for stream #{stream_id}"
  end

  def recv(%{id: id}, %{stream_id: stream_id}) when stream_id === 0 do
    raise "FATAL on stream #{id}: stream #{stream_id} is reserved"
  end

  # IDLE

  def recv(%{state: :idle, recv_hbf: recv_hbf} = stream,
  %Headers{payload: %{hbf: hbf}}) do
    {:ok, %{stream | state: :open, recv_hbf_type: :headers, recv_hbf: [hbf | recv_hbf]}}
  end

  # RESERVED_LOCAL

  def recv(%{state: :reserved_local} = stream, %Priority{}), do: {:ok, stream}
  def recv(%{state: :reserved_local} = stream, %RstStream{}), do: {:ok, %{stream | state: :closed}}
  def recv(%{state: :reserved_local, window_size: window_size} = stream,
  %WindowUpdate{payload: %{window_size_increment: increment}}) do
    {:ok, %{stream | window_size: window_size + increment}}
  end

  # RESERVED REMOTE

  def recv(%{state: :reserved_remote, recv_hbf: recv_hbf} = stream,
  %Headers{payload: %{hbf: hbf}}) do
    {:ok, %{stream | state: :half_closed_local, recv_hbf_type: :headers, recv_hbf: [hbf | recv_hbf]}}
  end
  def recv(%{state: :reserved_remote} = stream, %Priority{}), do: {:ok, stream}
  def recv(%{state: :reserved_remote} = stream, %RstStream{}), do: {:ok, %{stream | state: :closed}}

  # OPEN

  def recv(%{state: :open, recv_hbf: recv_hbf} = stream,
  %Headers{flags: %{end_stream: true}, payload: %{hbf: hbf}}) do
    recv_hbf = Enum.reverse([hbf | recv_hbf])
    {:ok, %{stream | state: :half_closed_remote, recv_hbf_type: :headers, recv_hbf: recv_hbf}}
  end

  def recv(%{state: :open, recv_hbf: recv_hbf} = stream,
  %Headers{flags: %{end_headers: true}, payload: %{hbf: hbf}}) do
    recv_hbf = Enum.reverse([hbf | recv_hbf])
    {:ok, %{stream | recv_hbf_type: :headers, recv_hbf: recv_hbf}}
  end

  def recv(%{state: :open, recv_hbf: recv_hbf} = stream,
  %PushPromise{flags: %{end_stream: true}, payload: %{hbf: hbf}}) do
    recv_hbf = Enum.reverse([hbf | recv_hbf])
    {:ok, %{stream | state: :half_closed_remote, recv_hbf_type: :push_promise, recv_hbf: recv_hbf}}
  end

  def recv(%{state: :open, recv_hbf: recv_hbf} = stream,
  %PushPromise{flags: %{end_headers: true}, payload: %{hbf: hbf}}) do
    recv_hbf = Enum.reverse([hbf | recv_hbf])
    {:ok, %{stream | recv_hbf_type: :push_promise, recv_hbf: recv_hbf}}
  end

  def recv(%{state: :open, recv_hbf: recv_hbf} = stream,
  %Continuation{flags: %{end_stream: true}, payload: %{hbf: hbf}}) do
    recv_hbf = Enum.reverse([hbf | recv_hbf])
    {:ok, %{stream | state: :half_closed_remote, recv_hbf: recv_hbf}}
  end

  def recv(%{state: :open, recv_hbf: recv_hbf} = stream,
  %Continuation{flags: %{end_headers: true}, payload: %{hbf: hbf}}) do
    recv_hbf = Enum.reverse([hbf | recv_hbf])
    {:ok, %{stream | recv_hbf: recv_hbf}}
  end

  def recv(%{state: :open, recv_hbf: recv_hbf} = stream,
  %Continuation{flags: %{end_headers: false}, payload: %{hbf: hbf}}) do
    {:ok, %{stream | recv_hbf: [hbf | recv_hbf]}}
  end

  def recv(%{state: :open, recv_data: recv_data} = stream,
  %Data{flags: %{end_stream: true}, payload: %{data: data}}) do
    recv_data = Enum.reverse([data | recv_data])
    {:ok, %{stream | state: :half_closed_remote, recv_data: recv_data}}
  end

  def recv(%{state: :open, recv_data: recv_data} = stream,
  %Data{flags: %{end_stream: false}, payload: %{data: data}}) do
    {:ok, %{stream | recv_data: [data | recv_data]}}
  end

  def recv(%{state: :open} = stream, %RstStream{}), do: {:ok, %{stream | state: :closed}}
  def recv(%{state: :open} = stream, _), do: {:ok, stream}

  # HALF CLOSED LOCAL

  def recv(%{state: :half_closed_local, recv_hbf: recv_hbf} = stream,
  %Headers{flags: %{end_stream: true}, payload: %{hbf: hbf}}) do
    recv_hbf = Enum.reverse([hbf | recv_hbf])
    {:ok, %{stream | state: :closed, recv_hbf_type: :headers, recv_hbf: recv_hbf}}
  end

  def recv(%{state: :half_closed_local, recv_data: recv_data} = stream,
  %Data{flags: %{end_stream: true}, payload: %{data: data}}) do
    recv_data = Enum.reverse([data | recv_data])
    {:ok, %{stream | state: :closed, recv_data: recv_data}}
  end

  def recv(%{state: :half_closed_local} = stream, %RstStream{}), do: {:ok, %{stream | state: :closed}}
  def recv(%{state: :half_closed_local} = stream, _), do: {:ok, stream}

  # HALF CLOSED REMOTE

  def recv(%{state: :half_closed_remote} = stream, %Priority{}), do: {:ok, stream}
  def recv(%{state: :half_closed_remote} = stream, %RstStream{}), do: {:ok, %{stream | state: :closed}}
  def recv(%{state: :half_closed_remote, window_size: window_size} = stream,
  %WindowUpdate{payload: %{window_size_increment: increment}}) do
    {:ok, %{stream | window_size: window_size + increment}}
  end
  def recv(%{state: :half_closed_remote}, _), do: {:error, :stream_closed}

  # CLOSED

  def recv(%{state: :closed} = stream, %Priority{}), do: {:ok, stream}
  def recv(%{state: :closed} = stream, %RstStream{}), do: {:ok, stream}
  def recv(%{state: :closed, window_size: window_size} = stream,
  %WindowUpdate{payload: %{window_size_increment: increment}}) do
    {:ok, %{stream | window_size: window_size + increment}}
  end
  def recv(%{state: :closed}, _), do: {:error, :stream_closed}

  # Stop on protocol error

  def recv(%{}, _), do: {:error, :protocol_error}

  @doc """
  Process sending one or more frame through the Stream state machine
  """
  @spec send(t, Frame.t | list(Frame.t)) :: {:ok, t} | error

  def send(stream, frames) when is_list(frames) do
    Enum.reduce_while(frames, {:ok, stream}, fn frame, _ ->
        with {:ok, stream} <- __MODULE__.send(stream, frame) do
          {:cont, {:ok, stream}}
        else
          error ->
            {:halt, error}
        end
      end)
  end

  def send(%{id: id}, %{stream_id: stream_id}) when stream_id !== id do
    raise "FATAL on stream #{id}: this frame was sent on #{stream_id}!"
  end

  def send(%{id: id}, %{stream_id: stream_id}) when stream_id === 0 do
    raise "FATAL on stream #{id}: stream id #{stream_id} is reserved!"
  end

  # IDLE

  def send(%{state: :idle} = stream, %Headers{} = frame) do
    send_frame(%{stream | state: :open}, frame)
  end

  # RESERVED LOCAL

  def send(%{state: :reserved_local} = stream, %Headers{} = frame) do
    send_frame(%{stream | state: :half_closed_remote}, frame)
  end

  def send(%{state: :reserved_local} = stream, %Priority{} = frame) do
    send_frame(stream, frame)
  end

  def send(%{state: :reserved_local} = stream, %RstStream{} = frame) do
    send_frame(%{stream | state: :closed}, frame)
  end

  # RESERVED REMOTE

  def send(%{state: :reserved_remote} = stream, %Priority{} = frame) do
    send_frame(stream, frame)
  end

  def send(%{state: :reserved_remote} = stream, %RstStream{} = frame) do
    send_frame(%{stream | state: :closed}, frame)
  end

  def send(%{state: :reserved_remote} = stream, %WindowUpdate{} = frame) do
    send_frame(stream, frame)
  end

  # OPEN

  def send(%{state: :open} = stream, %Data{flags: %{end_stream: true}} = frame) do
    send_frame(%{stream | state: :half_closed_local}, frame)
  end

  def send(%{state: :open} = stream, %Headers{flags: %{end_stream: true}} = frame) do
    send_frame(%{stream | state: :half_closed_local}, frame)
  end

  def send(%{state: :open} = stream, %RstStream{} = frame) do
    send_frame(%{stream | state: :closed}, frame)
  end

  def send(%{state: :open} = stream, frame) do
    send_frame(stream, frame)
  end

  # HALF CLOSED LOCAL

  def send(%{state: :half_closed_local} = stream, %Priority{} = frame) do
    send_frame(stream, frame)
  end

  def send(%{state: :half_closed_local} = stream, %RstStream{} = frame) do
    send_frame(%{stream | state: :closed}, frame)
  end

  def send(%{state: :half_closed_local} = stream, %WindowUpdate{} = frame) do
    send_frame(stream, frame)
  end

  # HALF CLOSED REMOTE

  def send(%{state: :half_closed_remote} = stream, %Data{flags: %{end_stream: true}} = frame) do
    send_frame(%{stream | state: :closed}, frame)
  end

  def send(%{state: :half_closed_remote} = stream, %Headers{flags: %{end_stream: true}} = frame) do
    send_frame(%{stream | state: :closed}, frame)
  end

  def send(%{state: :half_closed_remote} = stream, %RstStream{} = frame) do
    send_frame(%{stream | state: :closed}, frame)
  end

  def send(%{state: :half_closed_remote} = stream, frame) do
    send_frame(stream, frame)
  end

  # CLOSED

  def send(%{state: :closed} = stream, %Priority{} = frame) do
    send_frame(stream, frame)
  end

  # Stop on protocol error

  def send(%{}, _), do: {:error, :protocol_error}

  defp send_frame(%{connection: :ankh_test_mock_connection} = new_stream, _frame) do
    {:ok, new_stream}
  end

  defp send_frame(%{connection: connection, id: id} = new_stream, frame) do
    case Connection.send(connection, %{frame | stream_id: id}) do
      :ok ->
        Logger.debug fn -> "SENT FRAME #{inspect %{frame | stream_id: id}}" end
        {:ok, new_stream}
      error ->
        {:error, error}
    end
  end
end
