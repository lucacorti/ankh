defmodule Ankh.HTTP2.Stream do
  @moduledoc """
  HTTP/2 stream process

  Struct implementing the HTTP/2 stream state machine
  """

  require Logger

  alias Ankh.HTTP2.{Error, Frame}

  # credo:disable-for-next-line Credo.Check.Readability.AliasOrder
  alias Frame.{
    Data,
    Continuation,
    Headers,
    Priority,
    RstStream,
    WindowUpdate
  }

  @initial_window_size 65_535
  @max_window_size 2_147_483_647

  @typedoc "Stream states"
  @type state ::
          :idle
          | :open
          | :closed
          | :half_closed_local
          | :half_closed_remote
          | :reserved_remote
          | :reserved_local

  @typedoc "Stream id"
  @type id :: non_neg_integer()

  @typedoc "Stream HBF type"
  @type hbf_type :: :headers | :push_promise | nil

  @typedoc "Reserve mode"
  @type reserve_mode :: :local | :remote

  @type end_stream :: boolean()

  @type data_type :: :headers | :data | :push_promise

  @type data ::
          {data_type, reference, iodata(), end_stream}
          | {:error, reference, Error.t(), end_stream}

  defguard is_local_stream(last_local_stream_id, stream_id)
           when rem(last_local_stream_id, 2) == rem(stream_id, 2)

  @typedoc "Stream struct"
  @type t :: %__MODULE__{
          id: id(),
          recv_end_stream: boolean(),
          recv_hbf_type: hbf_type(),
          recv_hbf: iodata(),
          reference: reference(),
          state: state(),
          window_size: non_neg_integer()
        }
  defstruct id: 0,
            recv_end_stream: false,
            recv_hbf_type: nil,
            recv_hbf: [],
            reference: nil,
            state: :idle,
            window_size: @initial_window_size

  @doc """
  Starts a new stream fot the provided connection
  """
  @spec new(id(), integer) :: t
  def new(
        id,
        window_size
      ) do
    %__MODULE__{
      id: id,
      reference: make_ref(),
      window_size: window_size
    }
  end

  @doc """
  Adjusts the stream window size
  """
  @spec adjust_window_size(t(), integer, integer) :: t()
  def adjust_window_size(
        %{id: id, window_size: prev_window_size} = stream,
        old_window_size,
        new_window_size
      ) do
    window_size = prev_window_size + (new_window_size - old_window_size)

    Logger.debug(fn ->
      "STREAM #{id} window_size: #{prev_window_size} + (#{new_window_size} - #{old_window_size}) = #{
        window_size
      }"
    end)

    %{stream | window_size: window_size}
  end

  @doc """
  Process a received frame for the stream
  """
  @spec recv(t(), Frame.t()) :: {:ok, t(), data | nil} | {:error, any()}
  def recv(%{id: id, reference: reference, state: state} = stream, frame) do
    case recv_frame(%{state: new_state, recv_hbf_type: recv_hbf_type} = stream, frame) do
      {:ok, stream} ->
        Logger.debug(fn ->
          "STREAM #{id} #{inspect(state)} -> #{inspect(new_state)} hbf: #{inspect(recv_hbf_type)}"
        end)

        {:ok, stream, nil}

      {:ok, %{state: new_state, recv_hbf_type: recv_hbf_type} = stream, {type, data, end_stream}} ->
        Logger.debug(fn ->
          "STREAM #{id} #{inspect(state)} -> #{inspect(new_state)} hbf: #{inspect(recv_hbf_type)}"
        end)

        {:ok, stream, {type, reference, data, end_stream}}

      {:error, reason} = error ->
        Logger.error(fn ->
          "STREAM #{id} #{state} RECV ERROR #{inspect(reason)} ON #{inspect(frame)}"
        end)

        error
    end
  end

  # Stream ID validity checks

  defp recv_frame(%{id: id} = _stream, %{stream_id: stream_id}) when stream_id != id do
    raise "FATAL: tried to recv frame with stream id #{stream_id} on stream with id #{id}"
  end

  defp recv_frame(%{id: id} = _stream, %{stream_id: 0}) do
    raise "FATAL: tried to recv frame with stream id 0 on stream with id #{id}"
  end

  defp recv_frame(%{id: stream_id}, %{payload: %{stream_dependency: depended_id}})
       when stream_id == depended_id,
       do: {:error, :protocol_error}

  # CONTINUATION

  defp recv_frame(
         %{
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type,
           recv_end_stream: recv_end_stream
         } = stream,
         %Continuation{
           flags: %Continuation.Flags{end_headers: true},
           payload: %Continuation.Payload{hbf: hbf}
         }
       )
       when not is_nil(recv_hbf_type) do
    {
      :ok,
      %{stream | recv_hbf_type: nil, recv_hbf: []},
      {recv_hbf_type, Enum.reverse([hbf | recv_hbf]), recv_end_stream}
    }
  end

  defp recv_frame(
         %{
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Continuation{
           flags: %Continuation.Flags{end_headers: false},
           payload: %Continuation.Payload{hbf: hbf}
         }
       )
       when not is_nil(recv_hbf_type) do
    {:ok, %{stream | recv_hbf: [hbf | recv_hbf]}}
  end

  defp recv_frame(%{recv_hbf_type: recv_hbf_type}, _frame)
       when not is_nil(recv_hbf_type),
       do: {:error, :protocol_error}

  # WINDOW_UPDATE

  defp recv_frame(%{state: :idle} = _stream, %WindowUpdate{}) do
    {:error, :protocol_error}
  end

  defp recv_frame(_stream, %WindowUpdate{payload: %WindowUpdate.Payload{increment: 0}}) do
    {:error, :protocol_error}
  end

  defp recv_frame(%{window_size: window_size}, %WindowUpdate{
         payload: %WindowUpdate.Payload{increment: increment}
       })
       when window_size + increment > @max_window_size do
    {:error, :flow_control_error}
  end

  defp recv_frame(
         %{id: id, window_size: window_size} = stream,
         %WindowUpdate{
           payload: %WindowUpdate.Payload{increment: increment}
         }
       ) do
    new_window_size = window_size + increment

    Logger.debug(fn ->
      "STREAM #{id} window_size: #{window_size} + #{increment} = #{new_window_size}"
    end)

    {:ok, %{stream | window_size: new_window_size}}
  end

  # PRIORITY

  defp recv_frame(stream, %Priority{}), do: {:ok, stream}

  # RST_STREAM

  defp recv_frame(%{state: :idle} = _stream, %RstStream{}) do
    {:error, :protocol_error}
  end

  defp recv_frame(stream, %RstStream{payload: %RstStream.Payload{error_code: :no_error}}) do
    {:ok, %{stream | state: :closed}}
  end

  defp recv_frame(stream, %RstStream{payload: %RstStream.Payload{error_code: reason}}) do
    {:ok, %{stream | state: :closed}, {:error, reason, true}}
  end

  # IDLE

  defp recv_frame(
         %{
           state: :idle,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: true},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    {
      :ok,
      %{
        stream
        | state: :half_closed_remote,
          recv_hbf_type: nil,
          recv_end_stream: true,
          recv_hbf: []
      },
      {:headers, Enum.reverse([hbf | recv_hbf]), true}
    }
  end

  defp recv_frame(
         %{
           state: :idle,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: false},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    {
      :ok,
      %{
        stream
        | state: :open,
          recv_hbf_type: nil,
          recv_hbf: []
      },
      {:headers, Enum.reverse([hbf | recv_hbf]), false}
    }
  end

  defp recv_frame(
         %{
           state: :idle,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    {
      :ok,
      %{
        stream
        | state: :open,
          recv_hbf_type: :headers,
          recv_end_stream: end_stream,
          recv_hbf: [hbf | recv_hbf]
      }
    }
  end

  # RESERVED REMOTE

  defp recv_frame(
         %{state: :reserved_remote, recv_hbf: recv_hbf, recv_hbf_type: recv_hbf_type} = stream,
         %Headers{
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    {
      :ok,
      %{stream | state: :half_closed_local, recv_hbf_type: :headers, recv_hbf: [hbf | recv_hbf]}
    }
  end

  # OPEN / HALF_CLOSED_LOCAL

  defp recv_frame(
         %{
           state: state,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: true},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) and state in [:open, :half_closed_local] do
    {
      :ok,
      %{
        stream
        | state: if(state == :open, do: :half_closed_remote, else: :closed),
          recv_hbf_type: nil,
          recv_end_stream: true,
          recv_hbf: []
      },
      {:headers, Enum.reverse([hbf | recv_hbf]), true}
    }
  end

  defp recv_frame(
         %{
           state: state,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: false},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) and state in [:open, :half_closed_local] do
    {
      :ok,
      %{
        stream
        | recv_hbf_type: nil,
          recv_hbf: []
      },
      {:headers, Enum.reverse([hbf | recv_hbf]), false}
    }
  end

  defp recv_frame(
         %{
           state: state,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: true},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) and state in [:open, :half_closed_local] do
    {
      :ok,
      %{
        stream
        | state: if(state == :open, do: :half_closed_remote, else: :closed),
          recv_hbf_type: :headers,
          recv_end_stream: true,
          recv_hbf: [hbf | recv_hbf]
      }
    }
  end

  defp recv_frame(
         %{
           state: state,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: false},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) and state in [:open, :half_closed_local] do
    {
      :ok,
      %{
        stream
        | recv_hbf_type: :headers,
          recv_hbf: [hbf | recv_hbf]
      }
    }
  end

  defp recv_frame(
         %{state: state} = stream,
         %Data{
           flags: %Data.Flags{end_stream: true},
           payload: payload
         }
       )
       when state in [:open, :half_closed_local] do
    {
      :ok,
      %{stream | state: if(state == :open, do: :half_closed_remote, else: :closed)},
      {:data, (payload && payload.data) || "", true}
    }
  end

  defp recv_frame(
         %{state: state} = stream,
         %Data{
           flags: %Data.Flags{end_stream: false},
           payload: payload
         }
       )
       when state in [:open, :half_closed_local] do
    {:ok, stream, {:data, (payload && payload.data) || "", false}}
  end

  # HALF CLOSED REMOTE

  defp recv_frame(%{state: :half_closed_remote}, _frame), do: {:error, :stream_closed}

  # CLOSED

  defp recv_frame(%{state: :closed}, _frame), do: {:error, :stream_closed}

  # Otherwise this is a PROTOCOL_ERROR

  defp recv_frame(_stream, _frame), do: {:error, :protocol_error}

  @doc """
  Process and send a frame on the stream
  """
  @spec send(t(), Frame.t()) :: {:ok, t()} | {:error, any()}
  def send(%{id: id, state: state} = stream, %{stream_id: id} = frame) do
    case send_frame(stream, frame) do
      {:ok, %{state: new_state, recv_hbf_type: recv_hbf_type} = stream} ->
        Logger.debug(fn ->
          "STREAM #{id} #{inspect(state)} -> #{inspect(new_state)} hbf: #{inspect(recv_hbf_type)}"
        end)

        {:ok, stream}

      {:error, reason} = error ->
        Logger.error(fn ->
          "STREAM #{id} #{state} SEND ERROR #{inspect(reason)} ON #{inspect(frame)}"
        end)

        error
    end
  end

  defp send_frame(%{id: id} = _stream, %{stream_id: stream_id}) when stream_id != id do
    raise "FATAL: tried to recv frame with stream id #{stream_id} on stream with id #{id}"
  end

  defp send_frame(%{id: id} = _stream, %{stream_id: 0}) do
    raise "FATAL: tried to recv frame with stream id 0 on stream with id #{id}"
  end

  # RST_STREAM

  defp send_frame(stream, %RstStream{}), do: {:ok, %{stream | state: :closed}}

  # PRIORITY

  defp send_frame(stream, %Priority{}), do: {:ok, stream}

  # IDLE

  defp send_frame(
         %{state: :idle} = stream,
         %Headers{flags: %Headers.Flags{end_stream: true}}
       ) do
    {:ok, %{stream | state: :half_closed_local}}
  end

  defp send_frame(%{state: :idle} = stream, %Headers{}) do
    {:ok, %{stream | state: :open}}
  end

  defp send_frame(
         %{state: :idle} = stream,
         %Continuation{flags: %Continuation.Flags{end_headers: true}}
       ) do
    {:ok, %{stream | state: :open}}
  end

  defp send_frame(%{state: :idle} = stream, %Continuation{}) do
    {:ok, stream}
  end

  # RESERVED LOCAL

  defp send_frame(%{state: :reserved_local} = stream, %Headers{}) do
    {:ok, %{stream | state: :half_closed_remote}}
  end

  # RESERVED REMOTE

  defp send_frame(%{state: :reserved_remote} = stream, %WindowUpdate{} = _frame) do
    {:ok, stream}
  end

  # OPEN

  defp send_frame(%{state: :open} = stream, %Data{flags: %Data.Flags{end_stream: true}}) do
    {:ok, %{stream | state: :half_closed_local}}
  end

  defp send_frame(
         %{state: :open} = stream,
         %Headers{flags: %Headers.Flags{end_stream: true}}
       ) do
    {:ok, %{stream | state: :half_closed_local}}
  end

  defp send_frame(%{state: :open} = stream, _frame) do
    {:ok, stream}
  end

  # HALF CLOSED LOCAL

  defp send_frame(%{state: :half_closed_local} = stream, %WindowUpdate{}) do
    {:ok, stream}
  end

  # HALF CLOSED REMOTE

  defp send_frame(
         %{state: :half_closed_remote} = stream,
         %Data{flags: %Data.Flags{end_stream: true}}
       ) do
    {:ok, %{stream | state: :closed}}
  end

  defp send_frame(
         %{state: :half_closed_remote} = stream,
         %Headers{flags: %Headers.Flags{end_stream: true}}
       ) do
    {:ok, %{stream | state: :closed}}
  end

  defp send_frame(%{state: :half_closed_remote} = stream, _frame) do
    {:ok, stream}
  end

  # CLOSED

  defp send_frame(%{state: :closed}, _frame) do
    {:error, :stream_closed}
  end

  # Otherwise this is a PROTOCOL_ERROR

  defp send_frame(%{}, _), do: {:error, :protocol_error}
end
