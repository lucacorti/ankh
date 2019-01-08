defmodule Ankh.Stream do
  @moduledoc """
  HTTP/2 stream process

  Process implementing the HTTP/2 stream state machine
  """

  require Logger

  alias Ankh.{Connection, Frame}

  alias Ankh.Frame.{
    Data,
    Continuation,
    Headers,
    Priority,
    PushPromise,
    RstStream,
    Splittable,
    WindowUpdate
  }

  use GenServer

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
  @type t :: GenServer.server()

  @typedoc "Stream id"
  @type id :: integer

  @typedoc "Stream HBF type"
  @type hbf_type :: :headers | :push_promise

  @typedoc "Reserve mode"
  @type reserve_mode :: :local | :remote

  @doc """
  Starts a new stream fot the provided connection
  """
  @spec start_link(Connection.connection(), id(), pid, pid, integer, pid, GenServer.options()) ::
          GenServer.on_start()
  def start_link(
        connection,
        id,
        recv_table,
        send_table,
        max_frame_size,
        controlling_process,
        options \\ []
      ) do
    GenServer.start_link(
      __MODULE__,
      [
        connection: connection,
        id: id,
        recv_table: recv_table,
        send_table: send_table,
        max_frame_size: max_frame_size,
        controlling_process: controlling_process
      ],
      options
    )
  end

  @doc false
  def init(args) do
    {:ok,
     Enum.into(args, %{
       state: :idle,
       recv_hbf_type: nil,
       recv_hbf_es: false,
       recv_hbf: [],
       window_size: 2_147_483_647
     })}
  end

  @doc """
  Process a received frame for the stream
  """
  @spec recv(t(), integer, iodata) :: {:ok, state()} | {:error, term}
  def recv(stream, type, data), do: GenServer.call(stream, {:recv, type, data})

  @doc """
  Process and send a frame on the stream
  """
  @spec send(t(), Frame.t()) :: {:ok, state()} | {:error, term}
  def send(stream, frame), do: GenServer.call(stream, {:send, frame})

  @doc """
  Reserves the stream for push_promise
  """
  @spec reserve(t(), reserve_mode) :: term
  def reserve(stream, mode), do: GenServer.call(stream, {:reserve, mode})

  @doc """
  Closes the stream
  """
  @spec close(t()) :: term
  def close(stream), do: GenServer.call(stream, {:close})

  def handle_call({:reserve, :local}, _from, %{state: :idle} = state) do
    {:reply, {:ok, :reserved_local}, %{state | state: :reserved_local}}
  end

  def handle_call({:reserve, :remote}, _from, %{state: :idle} = state) do
    {:reply, {:ok, :reserved_remote}, %{state | state: :reserved_remote}}
  end

  def handle_call({:reserve, _mode}, _from, %{state: :idle} = state) do
    error = {:error, :invalid_reserve_mode}
    {:stop, error, error, state}
  end

  def handle_call({:reserve, _mode}, _from, state) do
    error = {:error, :stream_not_idle}
    {:stop, error, error, state}
  end

  def handle_call(
        {:recv, type, data},
        _from,
        %{
          id: id,
          state: old_stream_state,
          connection: connection,
          controlling_process: controlling_process
        } = state
      ) do
    case Frame.Registry.frame_for_type(connection, type) do
      nil ->
        {:reply, {:ok, old_stream_state}, state}

      type ->
        with {:ok, frame} <- Frame.decode(struct(type), data),
             {:ok, %{state: new_stream_state, recv_hbf_type: recv_hbf_type} = state} <-
               recv_frame(state, frame) do
          Logger.debug(fn ->
            "RECEIVED #{inspect(frame)}\nSTREAM #{inspect(old_stream_state)} -> #{
              inspect(new_stream_state)
            } receiving hbf: #{inspect(recv_hbf_type)}"
          end)

          {:reply, {:ok, new_stream_state}, state}
        else
          {:error, _} = error ->
            Logger.debug(fn ->
              "STREAM #{id} STATE #{old_stream_state} RECEIVE #{inspect(error)} FRAME #{
                inspect(type)
              } DATA #{inspect(data)}"
            end)

            Process.send(controlling_process, {:ankh, :error, id, error}, [])
            {:stop, error, error, state}
        end
    end
  end

  def handle_call(
        {:send, frame},
        _from,
        %{
          id: id,
          state: old_stream_state,
          controlling_process: controlling_process
        } = state
      ) do
    frame = %{frame | stream_id: id}

    case send_frame(state, frame) do
      {:ok, %{state: new_stream_state, recv_hbf_type: recv_hbf_type} = state} ->
        Logger.debug(fn ->
          "STREAM #{id}: #{inspect(old_stream_state)} -> #{inspect(new_stream_state)} receiving hbf: #{
            inspect(recv_hbf_type)
          }"
        end)

        {:reply, {:ok, new_stream_state}, state}

      {:error, _} = error ->
        Logger.debug(fn ->
          "STREAM #{id} STATE #{old_stream_state} SEND #{inspect(error)} FRAME #{inspect(frame)}"
        end)

        Process.send(controlling_process, {:ankh, :error, id, error}, [])
        {:stop, error, error, state}
    end
  end

  def handle_call({:close}, _from, state) do
    {:stop, :normal, :ok, state}
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

  defp recv_frame(_stream, %WindowUpdate{payload: %WindowUpdate.Payload{window_size_increment: 0}}) do
    {:error, :protocol_error}
  end

  # IDLE

  defp recv_frame(%{state: :idle} = state, %Priority{}), do: {:ok, state}

  defp recv_frame(
         %{
           id: id,
           state: :idle,
           recv_hbf: recv_hbf,
           recv_table: recv_table,
           controlling_process: controlling_process
         } = state,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       ) do
    stream_state = if end_stream, do: :half_closed_remote, else: :open

    case process_recv_headers([hbf | recv_hbf], recv_table) do
      {:ok, headers} ->
        Process.send(
          controlling_process,
          {:ankh, :headers, id, headers, end_stream},
          []
        )

        {:ok,
         %{
           state
           | state: stream_state,
             recv_hbf_type: nil,
             recv_hbf_es: false,
             recv_hbf: []
         }}

      :error ->
        {:error, :compression_error}
    end
  end

  defp recv_frame(
         %{
           state: :idle,
           recv_hbf: recv_hbf
         } = state,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       ) do
    stream_state = if end_stream, do: :half_closed_remote, else: :open

    {:ok,
     %{
       state
       | state: stream_state,
         recv_hbf_type: :headers,
         recv_hbf_es: end_stream,
         recv_hbf: [hbf | recv_hbf]
     }}
  end

  # RESERVED_LOCAL

  defp recv_frame(%{state: :reserved_local} = state, %Priority{}), do: {:ok, state}

  defp recv_frame(%{state: :reserved_local} = state, %RstStream{}) do
    {:ok, %{state | state: :closed}}
  end

  defp recv_frame(%{state: :reserved_local, window_size: window_size} = state, %WindowUpdate{
         payload: %WindowUpdate.Payload{window_size_increment: increment}
       }) do
    {:ok, %{state | window_size: window_size + increment}}
  end

  # RESERVED REMOTE

  defp recv_frame(%{state: :reserved_remote, recv_hbf: recv_hbf} = state, %Headers{
         payload: %Headers.Payload{hbf: hbf}
       }) do
    {:ok,
     %{state | state: :half_closed_local, recv_hbf_type: :headers, recv_hbf: [hbf | recv_hbf]}}
  end

  defp recv_frame(%{state: :reserved_remote} = state, %Priority{}), do: {:ok, state}

  defp recv_frame(%{state: :reserved_remote} = state, %RstStream{}) do
    {:ok, %{state | state: :closed}}
  end

  # OPEN

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf,
           recv_table: recv_table
         } = state,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       ) do
    stream_state = if end_stream, do: :half_closed_remote, else: :open

    case process_recv_headers([hbf | recv_hbf], recv_table) do
      {:ok, headers} ->
        Process.send(
          controlling_process,
          {:ankh, :headers, id, headers, end_stream},
          []
        )

        {:ok,
         %{
           state
           | state: stream_state,
             recv_hbf_type: nil,
             recv_hbf_es: false,
             recv_hbf: []
         }}

      :error ->
        {:error, :compression_error}
    end
  end

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf
         } = state,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       ) do
    stream_state = if end_stream, do: :half_closed_remote, else: :open

    {:ok,
     %{
       state
       | state: stream_state,
         recv_hbf_type: :headers,
         recv_hbf_es: end_stream,
         recv_hbf: [hbf | recv_hbf]
     }}
  end

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf,
           recv_table: recv_table
         } = state,
         %PushPromise{
           flags: %PushPromise.Flags{end_headers: true},
           payload: %PushPromise.Payload{hbf: hbf}
         }
       ) do
    case process_recv_headers([hbf | recv_hbf], recv_table) do
      {:ok, headers} ->
        Process.send(
          controlling_process,
          {:ankh, :push_promise, id, headers, true},
          []
        )

        {:ok,
         %{
           state
           | state: :half_closed_remote,
             recv_hbf_type: nil,
             recv_hbf_es: false,
             recv_hbf: []
         }}

      :error ->
        {:error, :compression_error}
    end
  end

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf
         } = state,
         %PushPromise{
           flags: %PushPromise.Flags{end_headers: false},
           payload: %PushPromise.Payload{hbf: hbf}
         }
       ) do
    {:ok,
     %{
       state
       | state: :half_closed_remote,
         recv_hbf_type: :push_promise,
         recv_hbf_es: false,
         recv_hbf: [hbf | recv_hbf]
     }}
  end

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type,
           recv_hbf_es: recv_hbf_es,
           recv_table: recv_table
         } = state,
         %Continuation{
           flags: %Continuation.Flags{end_headers: true},
           payload: %Continuation.Payload{hbf: hbf}
         }
       ) do
    case process_recv_headers([hbf | recv_hbf], recv_table) do
      {:ok, headers} ->
        Process.send(controlling_process, {:ankh, recv_hbf_type, id, headers, recv_hbf_es}, [])
        {:ok, %{state | recv_hbf_type: nil, recv_hbf_es: false, recv_hbf: []}}

      :error ->
        {:error, :compression_error}
    end
  end

  defp recv_frame(
         %{
           state: :open,
           recv_hbf: recv_hbf
         } = state,
         %Continuation{
           flags: %Continuation.Flags{end_headers: false},
           payload: %Continuation.Payload{hbf: hbf}
         }
       ) do
    {:ok, %{state | recv_hbf: [hbf | recv_hbf]}}
  end

  defp recv_frame(
         %{id: id, state: :open, controlling_process: controlling_process} = state,
         %Data{
           length: length,
           flags: %Data.Flags{end_stream: end_stream},
           payload: %Data.Payload{} = payload
         }
       ) do
    data = if not is_nil(payload) and not is_nil(payload.data), do: payload.data, else: ""
    Process.send(controlling_process, {:ankh, :data, id, data, end_stream}, [])
    state = process_recv_data(length, state)
    stream_state = if end_stream, do: :half_closed_remote, else: :open
    {:ok, %{state | state: stream_state}}
  end

  defp recv_frame(%{state: :open} = state, %RstStream{}) do
    {:ok, %{state | state: :closed}}
  end

  defp recv_frame(%{state: :open, recv_hbf_type: recv_hbf_type}, _)
       when not is_nil(recv_hbf_type),
       do: {:error, :protocol_error}

  defp recv_frame(%{state: :open} = state, _), do: {:ok, state}

  # HALF CLOSED LOCAL

  defp recv_frame(
         %{
           id: id,
           state: :half_closed_local,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf,
           recv_table: recv_table
         } = state,
         %Headers{
           flags: %Headers.Flags{end_headers: true, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       ) do
    stream_state = if end_stream, do: :closed, else: :half_closed_local

    case process_recv_headers([hbf | recv_hbf], recv_table) do
      {:ok, headers} ->
        Process.send(
          controlling_process,
          {:ankh, :headers, id, headers, end_stream},
          []
        )

        {:ok,
         %{
           state
           | state: stream_state,
             recv_hbf_type: nil,
             recv_hbf_es: false,
             recv_hbf: []
         }}

      :error ->
        {:error, :compression_error}
    end
  end

  defp recv_frame(
         %{
           state: :half_closed_local,
           recv_hbf: recv_hbf
         } = state,
         %Headers{
           flags: %Headers.Flags{end_headers: false, end_stream: end_stream},
           payload: %Headers.Payload{hbf: hbf}
         }
       ) do
    stream_state = if end_stream, do: :closed, else: :half_closed_local

    {:ok,
     %{
       state
       | state: stream_state,
         recv_hbf_type: :headers,
         recv_hbf_es: end_stream,
         recv_hbf: [hbf | recv_hbf]
     }}
  end

  defp recv_frame(
         %{
           state: :half_closed_local,
           id: id,
           controlling_process: controlling_process
         } = state,
         %Data{
           length: length,
           flags: %Data.Flags{end_stream: end_stream},
           payload: %Data.Payload{} = payload
         }
       ) do
    data = if not is_nil(payload) and not is_nil(payload.data), do: payload.data, else: ""
    Process.send(controlling_process, {:ankh, :data, id, data, end_stream}, [])
    state = process_recv_data(length, state)
    stream_state = if end_stream, do: :closed, else: :half_closed_local
    {:ok, %{state | state: stream_state}}
  end

  defp recv_frame(%{state: :half_closed_local} = state, %RstStream{}) do
    {:ok, %{state | state: :closed}}
  end

  defp recv_frame(%{state: :half_closed_local} = state, _), do: {:ok, state}

  # HALF CLOSED REMOTE

  defp recv_frame(
         %{
           id: id,
           state: :half_closed_remote,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf,
           recv_hbf_type: recv_hbf_type,
           recv_hbf_es: recv_hbf_es,
           recv_table: recv_table
         } = state,
         %Continuation{
           flags: %Continuation.Flags{end_headers: true},
           payload: %Continuation.Payload{hbf: hbf}
         }
       ) do
    case process_recv_headers([hbf | recv_hbf], recv_table) do
      {:ok, headers} ->
        Process.send(
          controlling_process,
          {:ankh, recv_hbf_type, id, headers, recv_hbf_es},
          []
        )

        {:ok, %{state | recv_hbf_type: nil, recv_hbf_es: false, recv_hbf: []}}

      :error ->
        {:error, :compression_error}
    end
  end

  defp recv_frame(
         %{
           state: :half_closed_remote,
           recv_hbf: recv_hbf
         } = state,
         %Continuation{
           flags: %Continuation.Flags{end_headers: false},
           payload: %Continuation.Payload{hbf: hbf}
         }
       ) do
    {:ok, %{state | recv_hbf: [hbf | recv_hbf]}}
  end

  defp recv_frame(%{state: :half_closed_remote} = state, %Priority{}), do: {:ok, state}

  defp recv_frame(%{state: :half_closed_remote} = state, %RstStream{}) do
    {:ok, %{state | state: :closed}}
  end

  defp recv_frame(%{state: :half_closed_remote, window_size: window_size} = state, %WindowUpdate{
         payload: %WindowUpdate.Payload{window_size_increment: increment}
       }) do
    {:ok, %{state | window_size: window_size + increment}}
  end

  defp recv_frame(%{state: :half_closed_remote}, _), do: {:error, :stream_closed}

  # CLOSED

  defp recv_frame(%{state: :closed} = state, %Priority{}), do: {:ok, state}
  defp recv_frame(%{state: :closed} = state, %RstStream{}), do: {:ok, state}

  defp recv_frame(%{state: :closed, window_size: window_size} = state, %WindowUpdate{
         payload: %WindowUpdate.Payload{window_size_increment: increment}
       }) do
    {:ok, %{state | window_size: window_size + increment}}
  end

  defp recv_frame(%{state: :closed}, _), do: {:error, :stream_closed}

  defp recv_frame(%{}, _), do: {:error, :protocol_error}

  defp send_frame(%{id: id}, %{stream_id: stream_id}) when stream_id !== id do
    {:error, :stream_id_mismatch}
  end

  defp send_frame(_state, %{stream_id: stream_id}) when stream_id === 0 do
    {:error, :stream_id_zero}
  end

  # IDLE

  defp send_frame(
         %{state: :idle} = state,
         %Headers{flags: %Headers.Flags{end_stream: true}} = frame
       ) do
    really_send_frame(%{state | state: :half_closed_local}, frame)
  end

  defp send_frame(%{state: :idle} = state, %Headers{} = frame) do
    really_send_frame(%{state | state: :open}, frame)
  end

  defp send_frame(
         %{state: :idle} = state,
         %Continuation{flags: %Continuation.Flags{end_headers: true}} = frame
       ) do
    really_send_frame(%{state | state: :open}, frame)
  end

  defp send_frame(%{state: :idle} = state, %Continuation{} = frame) do
    really_send_frame(state, frame)
  end

  # RESERVED LOCAL

  defp send_frame(%{state: :reserved_local} = state, %Headers{} = frame) do
    really_send_frame(%{state | state: :half_closed_remote}, frame)
  end

  defp send_frame(%{state: :reserved_local} = state, %Priority{} = frame) do
    really_send_frame(state, frame)
  end

  defp send_frame(%{state: :reserved_local} = state, %RstStream{} = frame) do
    really_send_frame(%{state | state: :closed}, frame)
  end

  # RESERVED REMOTE

  defp send_frame(%{state: :reserved_remote} = state, %Priority{} = frame) do
    really_send_frame(state, frame)
  end

  defp send_frame(%{state: :reserved_remote} = state, %RstStream{} = frame) do
    really_send_frame(%{state | state: :closed}, frame)
  end

  defp send_frame(%{state: :reserved_remote} = state, %WindowUpdate{} = frame) do
    really_send_frame(state, frame)
  end

  # OPEN

  defp send_frame(%{state: :open} = state, %Data{flags: %Data.Flags{end_stream: true}} = frame) do
    really_send_frame(%{state | state: :half_closed_local}, frame)
  end

  defp send_frame(
         %{state: :open} = state,
         %Headers{flags: %Headers.Flags{end_stream: true}} = frame
       ) do
    really_send_frame(%{state | state: :half_closed_local}, frame)
  end

  defp send_frame(%{state: :open} = state, %RstStream{} = frame) do
    really_send_frame(%{state | state: :closed}, frame)
  end

  defp send_frame(%{state: :open} = state, frame) do
    really_send_frame(state, frame)
  end

  # HALF CLOSED LOCAL

  defp send_frame(%{state: :half_closed_local} = state, %Priority{} = frame) do
    really_send_frame(state, frame)
  end

  defp send_frame(%{state: :half_closed_local} = state, %RstStream{} = frame) do
    really_send_frame(%{state | state: :closed}, frame)
  end

  defp send_frame(%{state: :half_closed_local} = state, %WindowUpdate{} = frame) do
    really_send_frame(state, frame)
  end

  # HALF CLOSED REMOTE

  defp send_frame(
         %{state: :half_closed_remote} = state,
         %Data{flags: %Data.Flags{end_stream: true}} = frame
       ) do
    really_send_frame(%{state | state: :closed}, frame)
  end

  defp send_frame(
         %{state: :half_closed_remote} = state,
         %Headers{flags: %Headers.Flags{end_stream: true}} = frame
       ) do
    really_send_frame(%{state | state: :closed}, frame)
  end

  defp send_frame(%{state: :half_closed_remote} = state, %RstStream{} = frame) do
    really_send_frame(%{state | state: :closed}, frame)
  end

  defp send_frame(%{state: :half_closed_remote} = state, frame) do
    really_send_frame(state, frame)
  end

  # CLOSED

  defp send_frame(%{state: :closed} = state, %Priority{} = frame) do
    really_send_frame(state, frame)
  end

  # Stop on protocol error

  defp send_frame(%{}, _), do: {:error, :protocol_error}

  defp really_send_frame(
         %{connection: connection, send_table: send_table, max_frame_size: max_frame_size} =
           state,
         frame
       ) do
    frame
    |> process_send_headers(send_table)
    |> Splittable.split(max_frame_size)
    |> Enum.reduce_while({:ok, nil}, fn frame, _ ->
      with {:ok, data} <- Frame.encode(frame),
           :ok <- Connection.send(connection, data) do
        Logger.debug(fn ->
          "SENT #{inspect(frame)}"
        end)

        {:cont, {:ok, state}}
      else
        error ->
          {:halt, error}
      end
    end)
  end

  defp process_recv_data(0, state), do: state

  defp process_recv_data(length, %{id: id} = state) do
    window_update = %WindowUpdate{
      payload: %WindowUpdate.Payload{
        window_size_increment: length
      }
    }

    with {:ok, _} <- really_send_frame(state, %{window_update | stream_id: 0}),
         {:ok, state} <- send_frame(state, %{window_update | stream_id: id}),
         do: state
  end

  defp process_recv_headers([<<>>], _recv_table), do: {:ok, []}

  defp process_recv_headers(hbf, recv_table) do
    try do
      headers =
        hbf
        |> Enum.reverse()
        |> Enum.join()
        |> HPack.decode(recv_table)

      if Enum.any?(headers, fn
           :none -> true
           _ -> false
         end) do
        :error
      else
        {:ok, headers}
      end
    rescue
      _ ->
        :error
    end
  end

  defp process_send_headers(%{payload: %{hbf: headers} = payload} = frame, send_table) do
    %{frame | payload: %{payload | hbf: HPack.encode(headers, send_table)}}
  end

  defp process_send_headers(frame, _send_table), do: frame
end
