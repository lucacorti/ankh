defmodule Ankh.HTTP2.Stream do
  @moduledoc """
  HTTP/2 stream process

  Struct implementing the HTTP/2 stream state machine
  """

  require Logger

  alias Ankh.HTTP2.Frame

  # credo:disable-for-next-line Credo.Check.Readability.AliasOrder
  alias Frame.{
    Data,
    Continuation,
    Headers,
    Priority,
    PushPromise,
    RstStream,
    WindowUpdate
  }

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

  @typedoc "Stream process"
  @type t :: %__MODULE__{}

  @typedoc "Stream id"
  @type id :: integer

  @typedoc "Stream HBF type"
  @type hbf_type :: :headers | :push_promise | nil

  @typedoc "Reserve mode"
  @type reserve_mode :: :local | :remote

  @type end_stream :: boolean()

  @type data_type :: :headers | :data | :push_promise

  @type data :: {data_type, iodata(), end_stream}

  defguard is_local_stream(last_local_stream_id, stream_id)
           when rem(last_local_stream_id, 2) == rem(stream_id, 2)

  defstruct id: 0,
            max_frame_size: 16_384,
            state: :idle,
            recv_hbf_type: nil,
            recv_hbf_es: false,
            recv_hbf: [],
            window_size: 65_535

  @doc """
  Starts a new stream fot the provided connection
  """
  @spec new(id(), integer, state) :: t
  def new(
        id,
        max_frame_size,
        state \\ :idle
      ) do
    %__MODULE__{
      id: id,
      state: state,
      max_frame_size: max_frame_size
    }
  end

  @doc """
  Process a received frame for the stream
  """
  @spec recv(t(), Frame.t()) :: {:ok, t()} | {:ok, t(), data} | {:error, any()}
  def recv(%{id: id, state: state} = stream, frame) do
    case recv_frame(stream, frame) do
      {:ok, %{state: new_state, recv_hbf_type: recv_hbf_type} = stream, data} ->
        Logger.debug(fn ->
          "STREAM #{id} RECEIVED #{inspect(frame)}\nSTREAM #{inspect(state)} -> #{
            inspect(new_state)
          } receiving hbf: #{inspect(recv_hbf_type)}"
        end)

        {:ok, stream, data}

      {:ok, stream} ->
        {:ok, stream, nil}

      {:error, reason} = error ->
        Logger.error(fn ->
          "STREAM #{id} STATE #{state} RECEIVE #{inspect(reason)} FRAME #{inspect(frame)}"
        end)

        error
    end
  end

  @doc """
  Process and send a frame on the stream
  """
  @spec send(t(), HTTP2.Frame.t()) :: {:ok, t()} | {:error, any()}
  def send(%{id: id, state: state} = stream, frame) do
    with frame <- %{frame | stream_id: id},
         {:ok, %{state: new_state, recv_hbf_type: recv_hbf_type} = stream} <-
           send_frame(stream, frame) do
      Logger.debug(fn ->
        "STREAM #{id}: #{inspect(state)} -> #{inspect(new_state)} receiving hbf: #{
          inspect(recv_hbf_type)
        }"
      end)

      {:ok, stream}
    else
      {:error, _} = error ->
        Logger.error(fn ->
          "STREAM #{id} STATE #{state} SEND #{inspect(error)} FRAME #{inspect(frame)}"
        end)

        error
    end
  end

  defp recv_frame(%{id: id}, %{stream_id: stream_id}) when stream_id !== id do
    {:error, :stream_id_mismatch}
  end

  defp recv_frame(_stream, %{stream_id: stream_id}) when stream_id === 0 do
    {:error, :stream_id_zero}
  end

  defp recv_frame(%{max_frame_size: max_frame_size}, %{length: length})
       when length > max_frame_size do
    {:error, :frame_size_error}
  end

  defp recv_frame(%{recv_hbf_type: recv_hbf_type}, %{type: type})
       when not is_nil(recv_hbf_type) and type !== 9,
       do: {:error, :protocol_error}

  defp recv_frame(%{id: stream_id}, %{payload: %{stream_dependency: depended_id}})
       when stream_id == depended_id,
       do: {:error, :protocol_error}

  defp recv_frame(%{id: stream_id, window_size: window_size} = stream, %WindowUpdate{
         payload: %WindowUpdate.Payload{increment: increment}
       })
       when window_size + increment > @max_window_size do
    rst_stream = %RstStream{
      stream_id: stream_id,
      payload: %RstStream.Payload{
        error_code: :flow_control_error
      }
    }

    with {:ok, _stream} <- send_frame(stream, rst_stream),
         do: {:error, :flow_control_error}
  end

  defp recv_frame(_stream, %WindowUpdate{payload: %WindowUpdate.Payload{increment: 0}}) do
    {:error, :protocol_error}
  end

  # IDLE

  defp recv_frame(%{state: :idle} = stream, %Priority{}), do: {:ok, stream}

  defp recv_frame(
         %{
           state: :idle,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    state = if end_stream, do: :half_closed_remote, else: :open

    {
      :ok,
      %{
        stream
        | state: state,
          recv_hbf_type: nil,
          recv_hbf_es: end_stream,
          recv_hbf: []
      },
      {:headers, [hbf | recv_hbf], end_stream}
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
          recv_hbf_es: end_stream,
          recv_hbf: [hbf | recv_hbf]
      }
    }
  end

  # RESERVED_LOCAL

  defp recv_frame(%{state: :reserved_local} = stream, %Priority{}), do: {:ok, stream}

  defp recv_frame(%{state: :reserved_local} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

  defp recv_frame(%{state: :reserved_local, window_size: window_size} = stream, %WindowUpdate{
         payload: %WindowUpdate.Payload{increment: increment}
       }) do
    {:ok, %{stream | window_size: window_size + increment}}
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

  defp recv_frame(%{state: :reserved_remote} = stream, %Priority{}), do: {:ok, stream}

  defp recv_frame(%{state: :reserved_remote} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

  # OPEN

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    state = if end_stream, do: :half_closed_remote, else: :open

    {
      :ok,
      %{
        stream
        | state: state,
          recv_hbf_type: nil,
          recv_hbf_es: false,
          recv_hbf: []
      },
      {:headers, [hbf | recv_hbf], end_stream}
    }
  end

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    state = if end_stream, do: :half_closed_remote, else: :open

    {
      :ok,
      %{
        stream
        | state: state,
          recv_hbf_type: :headers,
          recv_hbf_es: end_stream,
          recv_hbf: [hbf | recv_hbf]
      }
    }
  end

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf
         } = stream,
         %PushPromise{
           flags: %PushPromise.Flags{end_headers: true},
           payload: %PushPromise.Payload{hbf: hbf}
         }
       ) do
    {
      :ok,
      %{
        stream
        | state: :half_closed_remote,
          recv_hbf_type: nil,
          recv_hbf_es: false,
          recv_hbf: []
      },
      {:push_promise, [hbf | recv_hbf], true}
    }
  end

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf
         } = stream,
         %PushPromise{
           flags: %PushPromise.Flags{end_headers: false},
           payload: %PushPromise.Payload{hbf: hbf}
         }
       ) do
    {:ok,
     %{
       stream
       | state: :half_closed_remote,
         recv_hbf_type: :push_promise,
         recv_hbf_es: false,
         recv_hbf: [hbf | recv_hbf]
     }}
  end

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type,
           recv_hbf_es: recv_hbf_es
         } = stream,
         %Continuation{
           flags: %Continuation.Flags{end_headers: true},
           payload: %Continuation.Payload{hbf: hbf}
         }
       ) do
    {
      :ok,
      %{stream | recv_hbf_type: nil, recv_hbf_es: false, recv_hbf: []},
      {recv_hbf_type, [hbf | recv_hbf], recv_hbf_es}
    }
  end

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf
         } = stream,
         %Continuation{
           flags: %Continuation.Flags{end_headers: false},
           payload: %Continuation.Payload{hbf: hbf}
         }
       ) do
    {:ok, %{stream | recv_hbf: [hbf | recv_hbf]}}
  end

  defp recv_frame(
         %{state: :open} = stream,
         %Data{
           flags: %Data.Flags{end_stream: end_stream},
           payload: payload
         }
       ) do
    data = if not is_nil(payload) and not is_nil(payload.data), do: payload.data, else: ""
    state = if end_stream, do: :half_closed_remote, else: :open
    {:ok, %{stream | state: state}, {:data, data, end_stream}}
  end

  defp recv_frame(%{state: :open} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

  defp recv_frame(%{state: :open, recv_hbf_type: recv_hbf_type}, _)
       when not is_nil(recv_hbf_type),
       do: {:error, :protocol_error}

  defp recv_frame(%{state: :open} = stream, _), do: {:ok, stream}

  # HALF CLOSED LOCAL

  defp recv_frame(
         %{
           state: :half_closed_local,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    state = if end_stream, do: :closed, else: :half_closed_local

    {
      :ok,
      %{
        stream
        | state: state,
          recv_hbf_type: nil,
          recv_hbf_es: false,
          recv_hbf: []
      },
      {:headers, [hbf | recv_hbf], end_stream}
    }
  end

  defp recv_frame(
         %{
           state: :half_closed_local,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type
         } = stream,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       )
       when is_nil(recv_hbf_type) do
    state = if end_stream, do: :closed, else: :half_closed_local

    {
      :ok,
      %{
        stream
        | state: state,
          recv_hbf_type: :headers,
          recv_hbf_es: end_stream,
          recv_hbf: [hbf | recv_hbf]
      }
    }
  end

  defp recv_frame(
         %{state: :half_closed_local} = stream,
         %Data{
           flags: %Data.Flags{end_stream: end_stream},
           payload: payload
         }
       ) do
    data = if not is_nil(payload) and not is_nil(payload.data), do: payload.data, else: ""
    state = if end_stream, do: :closed, else: :half_closed_local
    {:ok, %{stream | state: state}, {:data, data, end_stream}}
  end

  defp recv_frame(%{state: :half_closed_local} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

  defp recv_frame(%{state: :half_closed_local} = stream, _), do: {:ok, stream}

  # HALF CLOSED REMOTE

  # defp recv_frame(
  #        %{
  #          state: :half_closed_remote,
  #          recv_hbf: recv_hbf,
  #          recv_hbf_type: recv_hbf_type,
  #          recv_hbf_es: recv_hbf_es
  #        } = stream,
  #        %Continuation{
  #          flags: %Continuation.Flags{end_headers: true},
  #          payload: %Continuation.Payload{hbf: hbf}
  #        }
  #      ) do
  #   {
  #     :ok,
  #     %{stream | recv_hbf_type: nil, recv_hbf_es: false, recv_hbf: []},
  #     {recv_hbf_type, [hbf | recv_hbf], recv_hbf_es}
  #   }
  # end

  # defp recv_frame(
  #        %{
  #          state: :half_closed_remote,
  #          recv_hbf: recv_hbf
  #        } = stream,
  #        %Continuation{
  #          flags: %Continuation.Flags{end_headers: false},
  #          payload: %Continuation.Payload{hbf: hbf}
  #        }
  #      ) do
  #   {:ok, %{stream | recv_hbf: [hbf | recv_hbf]}}
  # end

  defp recv_frame(%{state: :half_closed_remote} = stream, %Priority{}), do: {:ok, stream}

  defp recv_frame(%{state: :half_closed_remote} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

  defp recv_frame(%{state: :half_closed_remote, window_size: window_size} = stream, %WindowUpdate{
         payload: %WindowUpdate.Payload{increment: increment}
       }) do
    {:ok, %{stream | window_size: window_size + increment}}
  end

  defp recv_frame(%{state: :half_closed_remote}, _), do: {:error, :stream_closed}

  # CLOSED

  defp recv_frame(%{state: :closed} = stream, %Priority{}), do: {:ok, stream}
  defp recv_frame(%{state: :closed} = stream, %RstStream{}), do: {:ok, stream}

  defp recv_frame(%{state: :closed, window_size: window_size} = stream, %WindowUpdate{
         payload: %WindowUpdate.Payload{increment: increment}
       }) do
    {:ok, %{stream | window_size: window_size + increment}}
  end

  defp recv_frame(%{state: :closed}, _), do: {:error, :stream_closed}

  defp recv_frame(%{}, _), do: {:error, :protocol_error}

  defp send_frame(%{id: id}, %{stream_id: stream_id}) when stream_id !== id do
    {:error, :stream_id_mismatch}
  end

  defp send_frame(_stream, %{stream_id: stream_id}) when stream_id === 0 do
    {:error, :stream_id_zero}
  end

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

  defp send_frame(%{state: :reserved_local} = stream, %Priority{}) do
    {:ok, stream}
  end

  defp send_frame(%{state: :reserved_local} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

  # RESERVED REMOTE

  defp send_frame(%{state: :reserved_remote} = stream, %Priority{}) do
    {:ok, stream}
  end

  defp send_frame(%{state: :reserved_remote} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

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

  defp send_frame(%{state: :open} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

  defp send_frame(%{state: :open} = stream, _frame) do
    {:ok, stream}
  end

  # HALF CLOSED LOCAL

  defp send_frame(%{state: :half_closed_local} = stream, %Priority{}) do
    {:ok, stream}
  end

  defp send_frame(%{state: :half_closed_local} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

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

  defp send_frame(%{state: :half_closed_remote} = stream, %RstStream{}) do
    {:ok, %{stream | state: :closed}}
  end

  defp send_frame(%{state: :half_closed_remote} = stream, _frame) do
    {:ok, stream}
  end

  # CLOSED

  defp send_frame(%{state: :closed} = stream, %Priority{}) do
    {:ok, stream}
  end

  # Stop on protocol error

  defp send_frame(%{}, _), do: {:error, :protocol_error}
end
