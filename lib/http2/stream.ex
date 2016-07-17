defmodule Http2.Stream do
  alias Http2.Frame
  alias Http2.Frame.{Data, Headers}

  defstruct [id: 0, state: :idle, hbf: <<>>]

  def new(id), do: %__MODULE__{id: id}

  #
  # RECEIVING FRAMES
  #

  def received_frame(%__MODULE__{id: id}, %Frame{stream_id: stream_id})
  when stream_id !== id do
    raise "FATAL on stream #{id}: this frame was received on #{stream_id}!"
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
  %Frame{type: :headers, flags: %Headers.Flags{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_remote}}
  end

  def received_frame(%__MODULE__{state: :open} = stream,
  %Frame{type: :data, flags: %Data.Flags{end_stream: true}}) do
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
  %Frame{type: :headers, flags: %Headers.Flags{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def received_frame(%__MODULE__{state: :half_closed_local} = stream,
  %Frame{type: :data, flags: %Data.Flags{end_stream: true}}) do
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

  #
  # SENDING FRAMES
  #

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
  %Frame{type: :headers, flags: %Headers.Flags{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :half_closed_local}}
  end

  def send_frame(%__MODULE__{state: :open} = stream,
  %Frame{type: :data, flags: %Data.Flags{end_stream: true}}) do
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
  %Frame{type: :headers, flags: %Headers.Flags{end_stream: true}}) do
    {:ok, %__MODULE__{stream | state: :closed}}
  end

  def send_frame(%__MODULE__{state: :half_closed_remote} = stream,
  %Frame{type: :data, flags: %Data.Flags{end_stream: true}}) do
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
