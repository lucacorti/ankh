defmodule Ankh.HTTP2.Stream do
  @moduledoc """
  HTTP/2 stream process

  Struct implementing the HTTP/2 stream state machine
  """

  require Logger

  alias Ankh.HTTP2.{Error, Frame}

  alias Frame.{
    Continuation,
    Data,
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

  @type end_stream :: boolean()

  @type data_type :: :headers | :data | :push_promise

  @type data ::
          {data_type, reference, iodata(), end_stream()}
          | {:error, reference, Error.t(), end_stream()}

  @type window_size :: integer()

  @typedoc "Stream"
  @type t :: %__MODULE__{
          id: id(),
          recv_headers: boolean(),
          recv_end_stream: boolean(),
          recv_hbf_type: hbf_type(),
          recv_hbf: iodata(),
          reference: reference(),
          send_hbf_type: hbf_type(),
          state: state(),
          window_size: integer()
        }
  defstruct id: 0,
            recv_headers: false,
            recv_end_stream: false,
            recv_hbf_type: nil,
            recv_hbf: [],
            reference: nil,
            send_hbf_type: nil,
            state: :idle,
            window_size: @initial_window_size

  @doc "Guard to test if a stream id is locally originated"
  defguard is_local_stream(last_local_stream_id, stream_id)
           when rem(last_local_stream_id, 2) == rem(stream_id, 2)

  @doc """
  Starts a new stream fot the provided connection
  """
  @spec new(id(), window_size()) :: t
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
  @spec adjust_window_size(t(), window_size(), window_size()) :: t()
  def adjust_window_size(
        %{id: id, window_size: prev_window_size} = stream,
        old_window_size,
        new_window_size
      ) do
    window_size = prev_window_size + (new_window_size - old_window_size)

    Logger.debug(fn ->
      "STREAM #{id} SETTINGS window_size: #{prev_window_size} + (#{new_window_size} - #{
        old_window_size
      }) = #{window_size}"
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
          "STREAM #{id} #{inspect(state)} -> #{inspect(new_state)} hbf: #{inspect(recv_hbf_type)} ON RECV #{
            inspect(frame)
          }"
        end)

        {:ok, stream, nil}

      {:ok, %{state: new_state, recv_hbf_type: recv_hbf_type} = stream, {type, data, end_stream}} ->
        Logger.debug(fn ->
          "STREAM #{id} #{inspect(state)} -> #{inspect(new_state)} hbf: #{inspect(recv_hbf_type)} ON RECV #{
            inspect(frame)
          }"
        end)

        {:ok, stream, {type, reference, data, end_stream}}

      {:error, reason} = error ->
        Logger.error(fn ->
          "STREAM #{id} #{state} ERROR #{inspect(reason)} ON RECV #{inspect(frame)}"
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
       when not is_nil(recv_hbf_type),
       do: {:ok, %{stream | recv_hbf: [hbf | recv_hbf]}}

  defp recv_frame(%{recv_hbf_type: recv_hbf_type}, _frame)
       when not is_nil(recv_hbf_type),
       do: {:error, :protocol_error}

  # WINDOW_UPDATE

  defp recv_frame(%{state: :idle} = _stream, %WindowUpdate{}),
    do: {:error, :protocol_error}

  defp recv_frame(_stream, %WindowUpdate{payload: %WindowUpdate.Payload{increment: 0}}),
    do: {:error, :protocol_error}

  defp recv_frame(%{window_size: window_size}, %WindowUpdate{
         payload: %WindowUpdate.Payload{increment: increment}
       })
       when window_size + increment > @max_window_size,
       do: {:error, :flow_control_error}

  defp recv_frame(
         %{id: id, window_size: window_size} = stream,
         %WindowUpdate{
           payload: %WindowUpdate.Payload{increment: increment}
         }
       ) do
    new_window_size = window_size + increment

    Logger.debug(fn ->
      "STREAM #{id} WINDOW_UPDATE window_size: #{window_size} + #{increment} = #{new_window_size}"
    end)

    {:ok, %{stream | window_size: new_window_size}}
  end

  # PRIORITY

  defp recv_frame(stream, %Priority{}), do: {:ok, stream}

  # RST_STREAM

  defp recv_frame(%{state: :idle} = _stream, %RstStream{}),
    do: {:error, :protocol_error}

  defp recv_frame(stream, %RstStream{payload: %RstStream.Payload{error_code: :no_error}}),
    do: {:ok, %{stream | state: :closed}}

  defp recv_frame(stream, %RstStream{payload: %RstStream.Payload{error_code: reason}}),
    do: {:ok, %{stream | state: :closed}, {:error, reason, true}}

  # HEADERS

  defp recv_frame(
         %{
           state: state,
           recv_hbf: recv_hbf,
           recv_hbf_type: nil
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: true},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when state in [:idle, :open, :half_closed_local] do
    {
      :ok,
      %{
        stream
        | state: if(state == :half_closed_local, do: :closed, else: :half_closed_remote),
          recv_hbf_type: nil,
          recv_headers: true,
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
           recv_hbf_type: nil,
           recv_headers: false
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: false},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when state in [:idle, :open, :half_closed_local] do
    {
      :ok,
      %{
        stream
        | state: if(state == :idle, do: :open, else: state),
          recv_headers: true,
          recv_hbf_type: nil,
          recv_hbf: []
      },
      {:headers, Enum.reverse([hbf | recv_hbf]), false}
    }
  end

  defp recv_frame(
         %{
           state: state,
           recv_hbf: recv_hbf,
           recv_hbf_type: nil
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: true},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when state in [:idle, :open, :half_closed_local] do
    state =
      case state do
        :idle -> :open
        :open -> :half_closed_remote
        :half_closed_local -> :closed
      end

    {
      :ok,
      %{
        stream
        | state: state,
          recv_hbf_type: :headers,
          recv_end_stream: true,
          recv_headers: true,
          recv_hbf: [hbf | recv_hbf]
      }
    }
  end

  defp recv_frame(
         %{
           state: state,
           recv_headers: false,
           recv_hbf: recv_hbf,
           recv_hbf_type: nil
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: false},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when state in [:idle, :open, :half_closed_local] do
    {
      :ok,
      %{
        stream
        | state: if(state == :idle, do: :open, else: state),
          recv_hbf_type: :headers,
          recv_headers: true,
          recv_hbf: [hbf | recv_hbf]
      }
    }
  end

  # DATA

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
          "STREAM #{id} #{inspect(state)} -> #{inspect(new_state)} hbf: #{inspect(recv_hbf_type)} ON SEND #{
            inspect(frame)
          }"
        end)

        {:ok, stream}

      {:error, reason} = error ->
        Logger.error(fn ->
          "STREAM #{id} #{state} ERROR #{inspect(reason)} ON SEND #{inspect(frame)}"
        end)

        error
    end
  end

  defp send_frame(%{id: id} = _stream, %{stream_id: stream_id}) when stream_id != id,
    do: raise("FATAL: tried to send frame with stream id #{stream_id} on stream with id #{id}")

  defp send_frame(%{id: id} = _stream, %{stream_id: 0}),
    do: raise("FATAL: tried to send frame with stream id 0 on stream with id #{id}")

  # RST_STREAM

  defp send_frame(stream, %RstStream{}), do: {:ok, %{stream | state: :closed}}

  # PRIORITY

  defp send_frame(stream, %Priority{}), do: {:ok, stream}

  # WINDOW_UPDATE

  defp send_frame(stream, %WindowUpdate{}), do: {:ok, stream}

  # CONTINUATION

  defp send_frame(
         %{send_hbf_type: send_hbf_type} = stream,
         %Continuation{flags: %Continuation.Flags{end_headers: end_headers}}
       )
       when not is_nil(send_hbf_type),
       do: {:ok, %{stream | send_hbf_type: if(end_headers, do: nil, else: send_hbf_type)}}

  defp send_frame(%{send_hbf_type: send_hbf_type}, _frame)
       when not is_nil(send_hbf_type),
       do: {:error, :protocol_error}

  # HEADERS

  defp send_frame(
         %{state: state} = stream,
         %Headers{flags: %Headers.Flags{end_headers: end_headers, end_stream: end_stream}}
       )
       when state in [:idle, :open, :half_closed_remote] do
    state =
      case {state, end_stream} do
        {:half_closed_remote, true} -> :closed
        {_, true} -> :half_closed_local
        {:idle, false} -> :open
        {_, false} -> state
      end

    {:ok,
     %{
       stream
       | state: state,
         send_hbf_type: if(end_headers, do: nil, else: :headers)
     }}
  end

  # DATA

  defp send_frame(
         %{id: stream_id, state: state, window_size: window_size} = stream,
         %Data{length: length, flags: %Data.Flags{end_stream: end_stream}}
       )
       when state in [:open, :half_closed_remote] do
    state =
      case {state, end_stream} do
        {:open, true} -> :half_closed_remote
        {_, true} -> :closed
        _ -> state
      end

    new_window_size = window_size - length

    Logger.debug(fn ->
      "STREAM #{stream_id} window_size after send: #{window_size} - #{length} = #{new_window_size}"
    end)

    {:ok, %{stream | state: state, window_size: new_window_size}}
  end

  # HALF CLOSED LOCAL

  defp send_frame(%{state: :half_closed_local}, _frame), do: {:error, :stream_closed}

  # CLOSED

  defp send_frame(%{state: :closed}, _frame), do: {:error, :stream_closed}

  # Otherwise this is a PROTOCOL_ERROR

  defp send_frame(%{}, _), do: {:error, :protocol_error}
end
