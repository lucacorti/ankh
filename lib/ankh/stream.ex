defmodule Ankh.Stream do
  @moduledoc """
  HTTP/2 Stream strucure
  """

  alias Ankh.Frame

  @typedoc """
  - id: stream id
  - state: stream state
  - hbf_type: type of HBF being accumulated
  - hbf: HBF accumulator, for reassembly
  - data: DATA accumulator, for reassembly
  """
  @type t :: %__MODULE__{id: Integer.t, state: :idle | :open | :closed |
  :half_closed_local | :half_closed_remote | :reserved_remote | :reserved_local
  | atom, hbf_type: :headers | :push_promise, hbf: binary, data: binary,
  window_size: Integer.t}
  defstruct [id: 0, state: :idle, hbf_type: :headers, hbf: <<>>, data: <<>>,
  window_size: 65_535]

  @doc """
  Creates a new Stream

  Parameters:
    - id: stream id
    - state: stream state
  """
  @spec new(Integer.t, :idle | :open | :closed | :half_closed_local |
  :half_closed_remote | :reserved_remote | :reserved_local) :: t
  def new(id, state), do: %__MODULE__{id: id, state: state}

  @doc """
  Process the reception of a frame through the Stream state machine
  """
  @spec received_frame(t, Frame.t) :: t
  def received_frame(%__MODULE__{id: id}, %Frame{stream_id: stream_id})
  when stream_id !== id do
    raise "FATAL on stream #{id}: this frame has stream id #{stream_id}!"
  end

  # IDLE

  def received_frame(%__MODULE__{state: :idle} = stream, %Frame{type: :headers})
  do
    {:ok, %__MODULE__{stream | state: :open}}
  end

  # RESERVED_LOCAL

  def received_frame(%__MODULE__{state: :reserved_local} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :reserved_local} = stream,
  %Frame{type: :priority})  do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :reserved_local} = stream,
  %Frame{type: :window_update})  do
    {:ok, stream}
  end

  # RESERVED REMOTE

  def received_frame(%__MODULE__{state: :reserved_remote} = stream,
  %Frame{type: :headers}) do
    {:ok, %__MODULE__{stream | state: :half_closed_local}}
  end

  def received_frame(%__MODULE__{state: :reserved_remote} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :reserved_remote} = stream,
  %Frame{type: :priority})  do
    {:ok, stream}
  end

  # OPEN

  def received_frame(%__MODULE__{state: :open} = stream,
  %Frame{type: :headers, flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_remote}}
  end

  def received_frame(%__MODULE__{state: :open} = stream,
  %Frame{type: :data, flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_remote}}
  end

  def received_frame(%__MODULE__{state: :open} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :open} = stream, %Frame{}) do
    {:ok, stream}
  end

  # HALF CLOSED LOCAL

  def received_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Frame{type: :headers, flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Frame{type: :data, flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_local} = stream, %Frame{})
  do
    {:ok, stream}
  end

  # HALF CLOSED REMOTE

  def received_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Frame{type: :window_update}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Frame{type: :priority}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_remote}, %Frame{}) do
    {:error, :stream_closed}
  end

  # CLOSED

  def received_frame(%__MODULE__{state: :closed} = stream,
  %Frame{type: :priority}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :closed} = stream,
  %Frame{type: :window_update}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :closed} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, stream}
  end

  def received_frame(%__MODULE__{state: :closed}, %Frame{}) do
    {:error, :stream_closed}
  end

  # Stop on protocol error

  def received_frame(%__MODULE__{}, %Frame{}) do
    {:error, :protocol_error}
  end

  @doc """
  Process sending a frame through the Stream state machine
  """
  @spec send_frame(t, Frame.t) :: t
  def send_frame(%__MODULE__{id: id}, %Frame{stream_id: stream_id})
  when stream_id !== id do
    raise "FATAL on stream #{id}: this frame was sent on #{stream_id}!"
  end

  # IDLE

  def send_frame(%__MODULE__{state: :idle} = stream, %Frame{type: :headers}) do
    {:ok, %__MODULE__{stream | state: :open}}
  end

  # RESERVED LOCAL

  def send_frame(%__MODULE__{state: :reserved_local} = stream,
  %Frame{type: :headers})
  do
    {:ok, %__MODULE__{stream | state: :half_closed_remote}}
  end

  def send_frame(%__MODULE__{state: :reserved_local} = stream,
  %Frame{type: :rst_stream})
  do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :reserved_local} = stream,
  %Frame{type: :priority}) do
    {:ok, stream}
  end

  # RESERVED REMOTE

  def send_frame(%__MODULE__{state: :reserved_remote} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :reserved_remote} = stream,
  %Frame{type: :priority})  do
    {:ok, stream}
  end

  def send_frame(%__MODULE__{state: :reserved_remote} = stream,
  %Frame{type: :window_update})  do
    {:ok, stream}
  end

  # OPEN

  def send_frame(%__MODULE__{state: :open} = stream,
  %Frame{type: :headers, flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_local}}
  end

  def send_frame(%__MODULE__{state: :open} = stream,
  %Frame{type: :data, flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_local}}
  end

  def send_frame(%__MODULE__{state: :open} = stream, %Frame{type: :rst_stream})
  do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :open} = stream, %Frame{}) do
    {:ok, stream}
  end

  # HALF CLOSED LOCAL

  def send_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Frame{type: :window_update}) do
    {:ok, stream}
  end

  def send_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Frame{type: :priority}) do
    {:ok, stream}
  end

  def send_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  # HALF CLOSED REMOTE

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Frame{type: :headers, flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Frame{type: :data, flags: %{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Frame{type: :rst_stream}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream, %Frame{}) do
    {:ok, stream}
  end

  # CLOSED

  def send_frame(%__MODULE__{state: :closed} = stream, %Frame{type: :priority})
  do
    {:ok, stream}
  end

  # Stop on protocol error

  def send_frame(%__MODULE__{}, %Frame{}) do
    {:error, :protocol_error}
  end
end
