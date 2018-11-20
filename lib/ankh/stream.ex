defmodule Ankh.Stream do
  @moduledoc false

  alias Ankh.{Connection, Frame}
  alias Frame.{Data, Continuation, Headers, Priority, PushPromise, RstStream, WindowUpdate}

  use GenServer
  require Logger

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

  @typedoc "Stream HBF type"
  @type hbf_type :: :headers | :push_promise

  @typedoc "Stream mode"
  @type mode :: :reassemble | :streaming

  @typedoc "Reserve mode"
  @type reserve_mode :: :local | :remote

  @spec start_link(Connection.t(), Integer.t(), pid, mode) :: GenServer.on_start()
  def start_link(connection, id, hpack_table, controlling_process \\ nil, mode \\ :reassemble) do
    GenServer.start_link(
      __MODULE__,
      [
        connection: connection,
        hpack_table: hpack_table,
        controlling_process: controlling_process || self(),
        id: id,
        mode: mode
      ],
      name: {:via, Registry, {__MODULE__.Registry, {connection, id}}}
    )
  end

  def init(
        connection: connection,
        hpack_table: hpack_table,
        controlling_process: controlling_process,
        id: id,
        mode: mode
      ) do
    {:ok,
     %{
       id: id,
       connection: connection,
       controlling_process: controlling_process,
       hpack_table: hpack_table,
       state: :idle,
       mode: mode,
       recv_hbf_type: :headers,
       recv_hbf: [],
       recv_data: [],
       window_size: 2_147_483_647
     }}
  end

  @spec recv(t(), Frame.t()) :: GenServer.on_call()
  def recv(stream, frame), do: GenServer.call(stream, {:recv, frame})

  @spec send(t(), Frame.t() | list(Frame.t())) :: GenServer.on_call()
  def send(stream, frame), do: GenServer.call(stream, {:send, frame})

  @spec reserve(t(), reserve_mode) :: GenServer.on_call()
  def reserve(stream, mode), do: GenServer.call(stream, {:reserve, mode})

  def handle_call({:reserve, :local}, _from, %{state: :idle} = state) do
    {:reply, {:ok, :reserved_local}, %{state | state: :reserved_local}}
  end

  def handle_call({:reserve, :remote}, _from, %{state: :idle} = state) do
    {:reply, {:ok, :reserved_remote}, %{state | state: :reserved_remote}}
  end

  def handle_call({:reserve, _mode}, _from, %{state: :idle} = state) do
    {:stop, {:error, :invalid_reserve_mode}, state}
  end

  def handle_call({:reserve, _mode}, _from, state) do
    {:stop, {:error, :stream_not_idle}, state}
  end

  def handle_call({:recv, frame}, _from, state) do
    case recv_frame(state, frame) do
      {:ok, %{state: stream_state} = state} ->
        {:reply, {:ok, stream_state}, state}

      {:error, _} = error ->
        {:stop, :normal, error, state}
    end
  end

  def handle_call({:send, frame}, _from, %{id: id} = state) do
    case send_frame(state, %{frame | stream_id: id}) do
      {:ok, %{state: stream_state} = new_state} ->
        {:reply, {:ok, stream_state}, new_state}

      {:error, _} = error ->
        {:stop, :normal, error, state}
    end
  end

  defp recv_frame(%{id: id}, %{stream_id: stream_id}) when stream_id !== id do
    {:error, :stream_id_mismatch}
  end

  defp recv_frame(_stream, %{stream_id: stream_id}) when stream_id === 0 do
    {:error, :stream_id_zero}
  end

  # IDLE

  defp recv_frame(
         %{
           id: id,
           state: :idle,
           recv_hbf: recv_hbf,
           controlling_process: controlling_process
         } = state,
         %Headers{
           flags: %{end_headers: true, end_stream: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, :headers, id, headers}, [])
    {:ok, %{state | state: :half_closed_remote, recv_hbf_type: :headers, recv_hbf: []}}
  end

  defp recv_frame(
         %{
           id: id,
           state: :idle,
           recv_hbf: recv_hbf,
           controlling_process: controlling_process
         } = state,
         %Headers{
           flags: %{end_headers: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, :headers, id, headers}, [])
    {:ok, %{state | state: :open, recv_hbf_type: :headers, recv_hbf: []}}
  end

  defp recv_frame(%{state: :idle, recv_hbf: recv_hbf} = state, %Headers{
         flags: %{end_stream: true},
         payload: %{hbf: hbf}
       }) do
    {:ok,
     %{state | state: :half_closed_remote, recv_hbf_type: :headers, recv_hbf: [hbf | recv_hbf]}}
  end

  defp recv_frame(%{state: :idle, recv_hbf: recv_hbf} = state, %Headers{payload: %{hbf: hbf}}) do
    {:ok, %{state | state: :open, recv_hbf_type: :headers, recv_hbf: [hbf | recv_hbf]}}
  end

  # RESERVED_LOCAL

  defp recv_frame(%{state: :reserved_local} = state, %Priority{}), do: {:ok, state}

  defp recv_frame(%{state: :reserved_local} = state, %RstStream{}),
    do: {:ok, %{state | state: :closed}}

  defp recv_frame(%{state: :reserved_local, window_size: window_size} = state, %WindowUpdate{
         payload: %{window_size_increment: increment}
       }) do
    {:ok, %{state | window_size: window_size + increment}}
  end

  # RESERVED REMOTE

  defp recv_frame(%{state: :reserved_remote, recv_hbf: recv_hbf} = state, %Headers{
         payload: %{hbf: hbf}
       }) do
    {:ok,
     %{state | state: :half_closed_local, recv_hbf_type: :headers, recv_hbf: [hbf | recv_hbf]}}
  end

  defp recv_frame(%{state: :reserved_remote} = state, %Priority{}), do: {:ok, state}

  defp recv_frame(%{state: :reserved_remote} = state, %RstStream{}),
    do: {:ok, %{state | state: :closed}}

  # OPEN

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf
         } = state,
         %Headers{
           flags: %{end_stream: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, :headers, id, headers}, [])
    {:ok, %{state | state: :half_closed_remote, recv_hbf_type: :headers, recv_hbf: []}}
  end

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf
         } = state,
         %Headers{
           flags: %{end_headers: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, :headers, id, headers}, [])
    {:ok, %{state | recv_hbf_type: :headers, recv_hbf: []}}
  end

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf
         } = state,
         %PushPromise{
           flags: %{end_stream: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, :headers, id, headers}, [])
    {:ok, %{state | state: :half_closed_remote, recv_hbf_type: :push_promise, recv_hbf: []}}
  end

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf
         } = state,
         %PushPromise{
           flags: %{end_headers: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, :push_promise, id, headers}, [])
    {:ok, %{state | recv_hbf_type: :push_promise, recv_hbf: []}}
  end

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf,
           recv_hbf_type: hbf_type
         } = state,
         %Continuation{
           flags: %{end_stream: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, hbf_type, id, headers}, [])
    {:ok, %{state | state: :half_closed_remote, recv_hbf: []}}
  end

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf,
           recv_hbf_type: hbf_type
         } = state,
         %Continuation{
           flags: %{end_headers: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, hbf_type, id, headers}, [])
    {:ok, %{state | recv_hbf: []}}
  end

  defp recv_frame(%{state: :open, recv_hbf: recv_hbf} = state, %Continuation{
         flags: %{end_headers: false},
         payload: %{hbf: hbf}
       }) do
    {:ok, %{state | recv_hbf: [hbf | recv_hbf]}}
  end

  defp recv_frame(
         %{
           id: id,
           state: :open,
           controlling_process: controlling_process,
           recv_data: recv_data
         } = state,
         %Data{
           flags: %{end_stream: true},
           payload: %{data: data}
         }
       ) do
    data =
      [data | recv_data]
      |> Enum.reverse()

    Process.send(controlling_process, {:ankh, :data, id, data}, [])
    {:ok, %{state | state: :half_closed_remote, recv_data: []}}
  end

  defp recv_frame(%{state: :open, recv_data: recv_data} = state, %Data{
         flags: %{end_stream: false},
         payload: %{data: data}
       }) do
    {:ok, %{state | recv_data: [data | recv_data]}}
  end

  defp recv_frame(%{state: :open} = state, %RstStream{}), do: {:ok, %{state | state: :closed}}
  defp recv_frame(%{state: :open} = state, _), do: {:ok, state}

  # HALF CLOSED LOCAL

  defp recv_frame(
         %{
           id: id,
           state: :half_closed_local,
           controlling_process: controlling_process,
           recv_hbf: recv_hbf
         } = state,
         %Headers{
           flags: %{end_stream: true},
           payload: %{hbf: hbf}
         }
       ) do
    headers =
      [hbf | recv_hbf]
      |> process_headers(state)

    Process.send(controlling_process, {:ankh, :headers, id, headers}, [])
    {:ok, %{state | state: :closed, recv_hbf_type: :headers, recv_hbf: []}}
  end

  defp recv_frame(
         %{
           id: id,
           state: :half_closed_local,
           controlling_process: controlling_process,
           recv_data: recv_data
         } = state,
         %Data{
           flags: %{end_stream: true},
           payload: %{data: data}
         }
       ) do
    recv_data = Enum.reverse([data | recv_data])
    Process.send(controlling_process, {:ankh, :data, id, recv_data}, [])
    {:ok, %{state | state: :closed, recv_data: []}}
  end

  defp recv_frame(%{state: :half_closed_local} = state, %RstStream{}),
    do: {:ok, %{state | state: :closed}}

  defp recv_frame(%{state: :half_closed_local} = state, _), do: {:ok, state}

  # HALF CLOSED REMOTE

  defp recv_frame(%{state: :half_closed_remote} = state, %Priority{}), do: {:ok, state}

  defp recv_frame(%{state: :half_closed_remote} = state, %RstStream{}),
    do: {:ok, %{state | state: :closed}}

  defp recv_frame(%{state: :half_closed_remote, window_size: window_size} = state, %WindowUpdate{
         payload: %{window_size_increment: increment}
       }) do
    {:ok, %{state | window_size: window_size + increment}}
  end

  defp recv_frame(%{state: :half_closed_remote}, _), do: {:error, :stream_closed}

  # CLOSED

  defp recv_frame(%{state: :closed} = state, %Priority{}), do: {:ok, state}
  defp recv_frame(%{state: :closed} = state, %RstStream{}), do: {:ok, state}

  defp recv_frame(%{state: :closed, window_size: window_size} = state, %WindowUpdate{
         payload: %{window_size_increment: increment}
       }) do
    {:ok, %{state | window_size: window_size + increment}}
  end

  defp recv_frame(%{state: :closed}, _), do: {:error, :stream_closed}

  # Stop on protocol error

  defp recv_frame(%{}, _), do: {:error, :protocol_error}

  defp send_frame(%{id: id}, %{stream_id: stream_id}) when stream_id !== id do
    {:error, :stream_id_mismatch}
  end

  defp send_frame(_state, %{stream_id: stream_id}) when stream_id === 0 do
    {:error, :stream_id_zero}
  end

  # IDLE

  defp send_frame(%{state: :idle} = state, %Headers{flags: %{end_stream: true}} = frame) do
    really_send_frame(%{state | state: :half_closed_local}, frame)
  end

  defp send_frame(%{state: :idle} = state, %Headers{} = frame) do
    really_send_frame(%{state | state: :open}, frame)
  end

  defp send_frame(%{state: :idle} = state, %Continuation{flags: %{end_stream: true}} = frame) do
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

  defp send_frame(%{state: :open} = state, %Data{flags: %{end_stream: true}} = frame) do
    really_send_frame(%{state | state: :half_closed_local}, frame)
  end

  defp send_frame(%{state: :open} = state, %Headers{flags: %{end_stream: true}} = frame) do
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
         %Data{flags: %{end_stream: true}} = frame
       ) do
    really_send_frame(%{state | state: :closed}, frame)
  end

  defp send_frame(
         %{state: :half_closed_remote} = state,
         %Headers{flags: %{end_stream: true}} = frame
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

  defp really_send_frame(%{connection: Ankh.Connection.Mock} = state, _frame) do
    {:ok, state}
  end

  defp really_send_frame(%{connection: connection} = state, frame) do
    case Connection.send(connection, frame) do
      :ok ->
        {:ok, state}

      error ->
        {:error, error}
    end
  end

  defp process_headers([<<>>], _state), do: %{}

  defp process_headers(hbf, %{hpack_table: table}) do
    hbf
    |> Enum.reverse()
    |> Enum.join()
    |> HPack.decode(table)
    |> Enum.into(%{})
  end
end
