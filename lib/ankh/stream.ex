defmodule Ankh.Stream do
  @moduledoc """
  HTTP/2 Stream strucure
  """

  alias Ankh.Frame
  alias Frame.{Error, Data, Headers, Priority, RstStream, WindowUpdate}

  @typedoc """
  Stream states
  """
  @type stream_state :: :idle | :open | :closed | :half_closed_local |
  :half_closed_remote | :reserved_remote | :reserved_local

  @typedoc """
  - id: stream id
  - state: stream state
  - hbf_type: type of HBF being accumulated
  - hbf: HBF accumulator, for reassembly
  - data: DATA accumulator, for reassembly
  - window_size: stream window size
  """
  @type t :: %__MODULE__{id: Integer.t, state: stream_state,
  hbf_type: :headers | :push_promise, hbf: binary, data: binary,
  window_size: Integer.t}

  defstruct [id: 0, state: :idle, hbf_type: :headers, hbf: <<>>, data: <<>>,
  window_size: 65_535]

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
  @spec new(Integer.t, stream_state) :: t
  def new(id, state), do: %__MODULE__{id: id, state: state}

  @doc """
  Process the reception of a frame through the Stream state machine
  """
  @spec received_frame(t, Frame.t) :: {:ok, t} | error

  def received_frame(%__MODULE__{id: id}, %{stream_id: stream_id})
  when stream_id !== id do
    raise "FATAL on stream #{id}: this frame has stream id #{stream_id}!"
  end

  def received_frame(%__MODULE__{id: id}, %{stream_id: stream_id})
  when stream_id === 0 do
    raise "FATAL on stream #{id}: stream id #{stream_id} is reserved!"
  end

  # IDLE

  def received_frame(%__MODULE__{state: :idle} = stream, %Headers{}) do
    {:ok, %__MODULE__{stream | state: :open}}
  end

  # RESERVED_LOCAL

  def received_frame(%__MODULE__{state: :reserved_local} = stream, %RstStream{})
  do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :reserved_local} = stream, %Priority{})
  do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :reserved_local} = stream,
  %WindowUpdate{})  do
    {:ok, stream}
  end

  # RESERVED REMOTE

  def received_frame(%__MODULE__{state: :reserved_remote} = stream, %Headers{})
  do
    {:ok, %__MODULE__{stream | state: :half_closed_local}}
  end

  def received_frame(%__MODULE__{state: :reserved_remote} = stream,
  %RstStream{}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :reserved_remote} = stream, %Priority{})
  do
    {:ok, stream}
  end

  # OPEN

  def received_frame(%__MODULE__{state: :open} = stream,
  %Headers{flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_remote}}
  end

  def received_frame(%__MODULE__{state: :open} = stream,
  %Data{flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_remote}}
  end

  def received_frame(%__MODULE__{state: :open} = stream, %RstStream{}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :open} = stream, _) do
    {:ok, stream}
  end

  # HALF CLOSED LOCAL

  def received_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Headers{flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Data{flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_local} = stream,
  %RstStream{}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_local} = stream, _) do
    {:ok, stream}
  end

  # HALF CLOSED REMOTE

  def received_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %WindowUpdate{}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Priority{}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %RstStream{}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_remote}, _) do
    {:error, :stream_closed}
  end

  # CLOSED

  def received_frame(%__MODULE__{state: :closed} = stream, %Priority{}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :closed} = stream, %WindowUpdate{}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :closed} = stream, %RstStream{}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :closed}, _) do
    {:error, :stream_closed}
  end

  # Stop on protocol error

  def received_frame(%__MODULE__{}, _) do
    {:error, :protocol_error}
  end

  @doc """
  Process sending a frame through the Stream state machine
  """
  @spec send_frame(t, Frame.t) :: {:ok, t} | error

  def send_frame(%__MODULE__{id: id}, %{stream_id: stream_id})
  when stream_id !== id do
    raise "FATAL on stream #{id}: this frame was sent on #{stream_id}!"
  end

  def send_frame(%__MODULE__{id: id}, %{stream_id: stream_id})
  when stream_id === 0 do
    raise "FATAL on stream #{id}: stream id #{stream_id} is reserved!"
  end

  # IDLE

  def send_frame(%__MODULE__{state: :idle} = stream, %Headers{}) do
    {:ok, %__MODULE__{stream | state: :open}}
  end

  # RESERVED LOCAL

  def send_frame(%__MODULE__{state: :reserved_local} = stream, %Headers{}) do
    {:ok, %__MODULE__{stream | state: :half_closed_remote}}
  end

  def send_frame(%__MODULE__{state: :reserved_local} = stream, %RstStream{}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :reserved_local} = stream, %Priority{}) do
    {:ok, stream}
  end

  # RESERVED REMOTE

  def send_frame(%__MODULE__{state: :reserved_remote} = stream, %RstStream{}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :reserved_remote} = stream, %Priority{})  do
    {:ok, stream}
  end

  def send_frame(%__MODULE__{state: :reserved_remote} = stream, %WindowUpdate{})
  do
    {:ok, stream}
  end

  # OPEN

  def send_frame(%__MODULE__{state: :open} = stream,
  %Headers{flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_local}}
  end

  def send_frame(%__MODULE__{state: :open} = stream,
  %Data{flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_local}}
  end

  def send_frame(%__MODULE__{state: :open} = stream, %RstStream{}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :open} = stream, _) do
    {:ok, stream}
  end

  # HALF CLOSED LOCAL

  def send_frame(%__MODULE__{state: :half_closed_local} = stream,
  %WindowUpdate{}) do
    {:ok, stream}
  end

  def send_frame(%__MODULE__{state: :half_closed_local} = stream, %Priority{})
  do
    {:ok, stream}
  end

  def send_frame(%__MODULE__{state: :half_closed_local} = stream, %RstStream{})
  do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  # HALF CLOSED REMOTE

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Headers{flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Data{flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream, %RstStream{})
  do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream, _) do
    {:ok, stream}
  end

  # CLOSED

  def send_frame(%__MODULE__{state: :closed} = stream, %Priority{}) do
    {:ok, stream}
  end

  # Stop on protocol error

  def send_frame(%__MODULE__{}, _) do
    {:error, :protocol_error}
  end
end
