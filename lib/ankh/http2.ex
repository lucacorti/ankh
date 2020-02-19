defmodule Ankh.HTTP2 do
  @moduledoc """
  HTTP/2 implementation
  """

  alias Ankh.{Protocol, TLS}
  alias Ankh.HTTP.{Request, Response}
  alias Ankh.HTTP2.Frame
  alias Ankh.HTTP2.Stream, as: HTTP2Stream

  alias Frame.{
    Data,
    GoAway,
    Headers,
    Ping,
    Priority,
    RstStream,
    Settings,
    Splittable,
    WindowUpdate
  }

  alias HPack.Table

  import Ankh.HTTP2.Stream, only: [is_local_stream: 2]

  require Logger

  @behaviour Protocol

  @initial_window_size 65_535
  @max_window_size 2_147_483_647
  @max_stream_id 2_147_483_647
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  @tls_options versions: [:"tlsv1.2"],
               ciphers: ['ECDHE-ECDSA-AES128-SHA256', 'ECDHE-ECDSA-AES128-SHA'],
               alpn_advertised_protocols: ["h2"]

  @default_settings [
    header_table_size: 4_096,
    enable_push: true,
    max_concurrent_streams: 128,
    initial_window_size: @initial_window_size,
    max_frame_size: 16_384,
    max_header_list_size: 128
  ]

  @opaque t :: %__MODULE__{}
  defstruct buffer: <<>>,
            last_stream_id: 0,
            last_local_stream_id: 0,
            last_remote_stream_id: 0,
            open_streams: 0,
            recv_hbf_type: nil,
            recv_hpack: nil,
            recv_settings: @default_settings,
            references: %{},
            send_hpack: nil,
            send_settings: @default_settings,
            socket: nil,
            streams: %{},
            transport: TLS,
            uri: nil,
            window_size: @initial_window_size

  @impl Protocol
  def new(options) do
    settings = Keyword.get(options, :settings, [])
    recv_settings = Keyword.merge(@default_settings, settings)

    with {:ok, send_hpack} <- Table.start_link(4_096),
         header_table_size <- Keyword.get(recv_settings, :header_table_size),
         {:ok, recv_hpack} <- Table.start_link(header_table_size) do
      {:ok,
       %__MODULE__{
         send_hpack: send_hpack,
         recv_hpack: recv_hpack,
         recv_settings: recv_settings
       }}
    end
  end

  @impl Protocol
  def accept(%{transport: transport} = protocol, uri, socket, options) do
    case transport.recv(socket, 24) do
      {:ok, @preface} ->
        with {:ok, protocol} <- send_settings(%{protocol | socket: socket}),
             {:ok, socket} <- transport.accept(socket, options) do
          {:ok, %{protocol | socket: socket, uri: uri}}
        end

      _ ->
        {:error, :protocol_error}
    end
  end

  @impl Protocol
  def close(%{transport: transport, socket: socket}) do
    transport.close(socket)
  end

  @impl Protocol
  def connect(%{transport: transport} = protocol, uri, options) do
    options = Keyword.merge(options, @tls_options)

    with {:ok, socket} <- transport.connect(uri, options),
         :ok <- transport.send(socket, @preface),
         {:ok, protocol} <-
           send_settings(%{protocol | last_local_stream_id: -1, uri: uri, socket: socket}) do
      {:ok, protocol}
    end
  end

  @impl Protocol
  def stream(%{buffer: buffer, transport: transport} = protocol, msg) do
    with {:ok, data} <- transport.handle_msg(msg),
         {:ok, protocol, responses} <- process_buffer(%{protocol | buffer: buffer <> data}) do
      {:ok, protocol, Enum.reverse(responses)}
    end
  end

  @impl Protocol
  def request(
        %{uri: %{authority: authority, scheme: scheme}} = protocol,
        %{method: method, path: path} = request
      ) do
    request =
      request
      |> Request.put_header(":method", Atom.to_string(method))
      |> Request.put_header(":authority", authority)
      |> Request.put_header(":scheme", scheme)
      |> Request.put_header(":path", path)

    with {:ok, protocol, %{reference: reference} = stream} <- get_stream(protocol, nil),
         {:ok, protocol} <- send_headers(protocol, stream, request),
         {:ok, protocol} <- send_data(protocol, stream, request),
         {:ok, protocol} <- send_trailers(protocol, stream, request) do
      {:ok, protocol, reference}
    end
  end

  @impl Protocol
  def respond(protocol, reference, %{status: status} = response) do
    response =
      response
      |> Response.put_header(":status", status)

      with {:ok, protocol, stream} <- get_stream(protocol, reference),
         {:ok, protocol} <- send_headers(protocol, stream, response),
         {:ok, protocol} <- send_data(protocol, stream, response),
         {:ok, protocol} <- send_trailers(protocol, stream, response) do
      {:ok, protocol}
    end
  end

  defp process_buffer(%{buffer: buffer, recv_settings: recv_settings} = protocol) do
    max_frame_size = Keyword.get(recv_settings, :max_frame_size)

    buffer
    |> Frame.stream()
    |> Enum.reduce_while({:ok, protocol, []}, fn
      {rest, nil}, {:ok, protocol, responses} ->
        {:halt, {:ok, %{protocol | buffer: rest}, responses}}

      {_rest, {length, _type, _id, _data}}, {:ok, protocol, _responses}
      when length > max_frame_size ->
        {:halt, send_error(protocol, :protocol_error)}

      {rest, {_length, type, _id, data}},
      {:ok, %{recv_hbf_type: recv_hbf_type} = protocol, responses} ->
        with {:ok, type} <- Frame.Registry.frame_for_type(protocol, type),
             {:ok, frame} <- Frame.decode(struct(type), data),
             :ok <- Logger.debug(fn -> "RECVD #{inspect(frame)} #{inspect(data)}" end),
             {:ok, protocol, responses} <- recv_frame(protocol, frame, responses) do
          {:cont, {:ok, %{protocol | buffer: rest}, responses}}
        else
          {:error, :not_found} when is_nil(recv_hbf_type) ->
            {:cont, {:ok, %{protocol | buffer: rest}, responses}}

          error ->
            {:halt, error}
        end
    end)
  end

  defp get_stream(%{references: references} = protocol, reference) when is_reference(reference) do
    stream_id = Map.get(references, reference)
    get_stream(protocol, stream_id)
  end

  defp get_stream(%{last_stream_id: last_stream_id}, id)
       when (not is_nil(id) and id >= @max_stream_id) or last_stream_id >= @max_stream_id do
    {:error, :stream_limit_reached}
  end

  defp get_stream(%{last_local_stream_id: last_local_stream_id} = protocol, nil = _id) do
    stream_id = last_local_stream_id + 2

    with {:ok, protocol, stream} <- new_stream(protocol, stream_id) do
      {:ok, %{protocol | last_local_stream_id: stream_id}, stream}
    end
  end

  defp get_stream(
         %{
           last_local_stream_id: last_local_stream_id,
           streams: streams
         } = protocol,
         stream_id
       ) do
    case Map.get(streams, stream_id) do
      stream when not is_nil(stream) ->
        {:ok, protocol, stream}

      nil when not is_local_stream(last_local_stream_id, stream_id) ->
        with {:ok, protocol, stream} <- new_stream(protocol, stream_id) do
          {:ok, protocol, stream}
        end

      _ ->
        {:error, :protocol_error}
    end
  end

  defp new_stream(
         %{references: references, send_settings: send_settings, streams: streams} = protocol,
         stream_id
       ) do
    window_size = Keyword.get(send_settings, :initial_window_size)
    stream = HTTP2Stream.new(stream_id, window_size)

    {
      :ok,
      %{
        protocol
        | references: Map.put(references, stream.reference, stream_id),
          streams: Map.put(streams, stream_id, stream)
      },
      stream
    }
  end

  defp send_frame(
         %{send_hpack: send_hpack} = protocol,
         %Headers{payload: %{hbf: headers} = payload} = frame
       )
       when is_list(headers) do
    do_send_frame(protocol, %{
      frame
      | payload: %{payload | hbf: HPack.encode(headers, send_hpack)}
    })
  end

  defp send_frame(%{window_size: window_size} = protocol, %Data{payload: %{data: data}} = frame) do
    do_send_frame(%{protocol | window_size: window_size - byte_size(data)}, frame)
  end

  defp send_frame(protocol, frame), do: do_send_frame(protocol, frame)

  defp do_send_frame(%{socket: socket, transport: transport} = protocol, %{stream_id: 0} = frame) do
    with {:ok, length, _type, data} <- Frame.encode(frame),
         :ok <- transport.send(socket, data) do
      Logger.debug(fn -> "SENT #{inspect(%{frame | length: length})} #{inspect(data)}" end)
      {:ok, protocol}
    end
  end

  defp do_send_frame(
         %{send_settings: send_settings, socket: socket, streams: streams, transport: transport} =
           protocol,
         %{stream_id: stream_id} = frame
       ) do
    max_frame_size = Keyword.get(send_settings, :max_frame_size)

    frame
    |> Splittable.split(max_frame_size)
    |> Enum.reduce_while({:ok, protocol}, fn frame, {:ok, protocol} ->
      with {:ok, length, _type, data} <- Frame.encode(frame),
           {:ok, protocol, stream} <- get_stream(protocol, stream_id),
           {:ok, stream} <- HTTP2Stream.send(stream, %{frame | length: length}),
           :ok <- transport.send(socket, data) do
        Logger.debug(fn -> "SENT #{inspect(%{frame | length: length})} #{inspect(data)}" end)

        {:cont, {:ok, %{protocol | streams: Map.put(streams, stream_id, stream)}}}
      else
        error ->
          {:halt, error}
      end
    end)
  end

  defp send_settings(%{send_hpack: send_hpack, recv_settings: recv_settings} = protocol) do
    header_table_size = Keyword.get(recv_settings, :header_table_size)

    with :ok <- Table.resize(header_table_size, send_hpack),
         {:ok, protocol} <-
           send_frame(protocol, %Settings{payload: %Settings.Payload{settings: recv_settings}}) do
      {:ok, protocol}
    else
      _ ->
        {:error, :compression_error}
    end
  end

  defp send_error(%{last_stream_id: last_stream_id} = protocol, reason) do
    with {:ok, _protocol} <-
           send_frame(protocol, %GoAway{
             payload: %GoAway.Payload{
               last_stream_id: last_stream_id,
               error_code: reason
             }
           }) do
      {:error, reason}
    end
  end

  defp send_stream_error(protocol, stream_id, reason) do
    send_frame(protocol, %RstStream{
      stream_id: stream_id,
      payload: %RstStream.Payload{error_code: reason}
    })
  end

  defp recv_frame(protocol, %{stream_id: 0} = frame, responses) do
    case process_connection_frame(frame, protocol) do
      {:ok, protocol} ->
        {:ok, protocol, responses}

      {:error, :not_found} ->
        {:ok, protocol, responses}

      {:error, reason} ->
        send_error(protocol, reason)
    end
  end

  defp recv_frame(
         %{last_local_stream_id: llid} = protocol,
         %{stream_id: stream_id} = frame,
         responses
       )
       when is_local_stream(llid, stream_id) do
    with {:ok, %{streams: streams} = protocol, stream} <- get_stream(protocol, stream_id),
         {:ok, %{recv_hbf_type: recv_hbf_type} = stream, response} <-
           HTTP2Stream.recv(stream, frame),
         {:ok, protocol, response} <- process_stream_response(protocol, frame, response) do
      {
        :ok,
        %{
          protocol
          | last_local_stream_id: max(llid, stream_id),
            recv_hbf_type: recv_hbf_type,
            streams: Map.put(streams, stream_id, stream)
        },
        [response | responses]
      }
    else
      {:ok, _stream} ->
        {:ok, protocol, responses}

      {:error, :not_found} ->
        send_error(protocol, :protocol_error)

      {:error, reason} ->
        send_error(protocol, reason)
    end
  end

  defp recv_frame(
         %{last_remote_stream_id: lrid, streams: streams} = protocol,
         %{stream_id: stream_id} = frame,
         responses
       ) do
    is_priority = Priority.type() == frame.type()

    with {:ok, protocol, stream} when is_priority or stream_id >= lrid <-
           get_stream(protocol, stream_id),
         {:ok, %{recv_hbf_type: recv_hbf_type} = stream, response} <-
           HTTP2Stream.recv(stream, frame),
         {:ok, protocol, response} <- process_stream_response(protocol, frame, response) do
      lrid = if is_priority, do: lrid, else: stream_id

      {
        :ok,
        %{
          protocol
          | last_remote_stream_id: lrid,
            recv_hbf_type: recv_hbf_type,
            streams: Map.put(streams, stream_id, stream)
        },
        [response | responses]
      }
    else
      {:ok, _stream} ->
        {:ok, protocol, responses}

      {:error, :flow_control_error = reason} ->
        send_stream_error(protocol, stream_id, reason)
        {:ok, protocol, responses}

      {:error, reason} ->
        send_error(protocol, reason)

      _stream ->
        send_error(protocol, :protocol_error)
    end
  end

  defp process_stream_response(
         protocol,
         %{length: 0},
         {:data, _ref, _hbf, _end_stream} = response
       ),
       do: {:ok, protocol, response}

  defp process_stream_response(
         protocol,
         %{lenght: length, stream_id: stream_id},
         {:data, _ref, _hbf, _end_stream} = response
       ) do
    window_update = %WindowUpdate{payload: %WindowUpdate.Payload{increment: length}}

    with {:ok, protocol} <- send_frame(protocol, window_update),
         {:ok, protocol} <- send_frame(protocol, %{window_update | stream_id: stream_id}) do
      {:ok, protocol, response}
    end
  end

  defp process_stream_response(protocol, _frame, {type, _ref, [<<>>], _end_stream} = response)
       when type in [:headers, :push_promise],
       do: {:ok, protocol, response}

  defp process_stream_response(
         %{recv_hpack: recv_hpack} = protocol,
         _frame,
         {type, ref, hbf, end_stream}
       )
       when type in [:headers, :push_promise] do
    headers =
      hbf
      |> Enum.join()
      |> HPack.decode(recv_hpack)

    if Enum.any?(headers, fn
         :none -> true
         {":path", ""} -> true
         _ -> false
       end) do
      {:error, :compression_error}
    else
      {:ok, protocol, {type, ref, headers, end_stream}}
    end
  rescue
    _ ->
      {:error, :compression_error}
  end

  defp process_stream_response(protocol, _frame, response), do: {:ok, protocol, response}

  defp process_connection_frame(
         %Settings{flags: %{ack: false}, payload: %{settings: settings}},
         %{send_settings: send_settings} = protocol
       ) do
    new_send_settings = Keyword.merge(send_settings, settings)

    old_header_table_size = Keyword.get(send_settings, :header_table_size)
    new_header_table_size = Keyword.get(new_send_settings, :header_table_size)
    old_window_size = Keyword.get(send_settings, :initial_window_size)
    new_window_size = Keyword.get(new_send_settings, :initial_window_size)

    settings_ack = %Settings{flags: %Settings.Flags{ack: true}, payload: nil}

    with {:ok, protocol} <- send_frame(protocol, settings_ack),
         {:ok, protocol} <-
           adjust_header_table_size(protocol, old_header_table_size, new_header_table_size),
         {:ok, protocol} <- adjust_window_size(protocol, old_window_size, new_window_size),
         {:ok, protocol} <- adjust_streams_window_size(protocol, old_window_size, new_window_size) do
      {:ok, %{protocol | send_settings: new_send_settings}}
    else
      _ ->
        {:error, :compression_error}
    end
  end

  defp process_connection_frame(%Settings{length: 0, flags: %{ack: true}}, protocol) do
    {:ok, protocol}
  end

  defp process_connection_frame(%Settings{flags: %{ack: true}}, _protocol) do
    {:error, :frame_size_error}
  end

  defp process_connection_frame(%Ping{length: 8, flags: %{ack: true}}, protocol) do
    {:ok, protocol}
  end

  defp process_connection_frame(%Ping{length: length}, _protocol) when length != 8 do
    {:error, :frame_size_error}
  end

  defp process_connection_frame(%Ping{flags: %{ack: false} = flags} = frame, protocol) do
    send_frame(protocol, %Ping{frame | flags: %{flags | ack: true}})
  end

  defp process_connection_frame(%WindowUpdate{length: length}, _protocol) when length != 4 do
    {:error, :frame_size_error}
  end

  defp process_connection_frame(
         %WindowUpdate{payload: %{increment: 0}},
         _protocol
       ) do
    {:error, :protocol_error}
  end

  defp process_connection_frame(
         %WindowUpdate{payload: %{increment: increment}},
         %{window_size: window_size} = protocol
       )
       when window_size + increment > @max_window_size do
    send_error(protocol, :flow_control_error)
  end

  defp process_connection_frame(
         %WindowUpdate{payload: %{increment: increment}},
         %{window_size: window_size} = protocol
       ) do
    new_window_size = window_size + increment
    Logger.debug(fn -> "window_size: #{window_size} + #{increment} = #{new_window_size}" end)
    {:ok, %{protocol | window_size: new_window_size}}
  end

  defp process_connection_frame(%GoAway{payload: %{error_code: reason}}, protocol) do
    Logger.error(fn -> "Received connection error #{inspect(reason)}, closing" end)
    with :ok <- close(protocol), do: {:ok, protocol}
  end

  defp process_connection_frame(_frame, _protocol) do
    {:error, :protocol_error}
  end

  defp send_headers(protocol, %{id: stream_id}, %{
         headers: headers,
         body: body
       }) do
    send_frame(protocol, %Headers{
      stream_id: stream_id,
      flags: %Headers.Flags{end_stream: is_nil(body)},
      payload: %Headers.Payload{hbf: headers}
    })
  end

  defp send_data(protocol, _stream, %{body: nil}), do: {:ok, protocol}

  defp send_data(protocol, %{id: stream_id}, %{body: body, trailers: trailers}) do
    send_frame(protocol, %Data{
      stream_id: stream_id,
      flags: %Data.Flags{end_stream: Enum.empty?(trailers)},
      payload: %Data.Payload{data: body}
    })
  end

  defp send_trailers(protocol, _stream, %{trailers: []}), do: {:ok, protocol}

  defp send_trailers(protocol, %{id: stream_id}, %{trailers: trailers}) do
    send_frame(protocol, %Headers{
      stream_id: stream_id,
      flags: %Headers.Flags{end_stream: true},
      payload: %Headers.Payload{hbf: trailers}
    })
  end

  defp adjust_header_table_size(%{send_hpack: send_hpack} = protocol, old_size, new_size)
       when new_size != old_size do
    with :ok <- Table.resize(new_size, send_hpack), do: {:ok, protocol}
  end

  defp adjust_header_table_size(protocol, _old_size, _new_size), do: {:ok, protocol}

  defp adjust_window_size(
         %{window_size: prev_window_size} = protocol,
         old_window_size,
         new_window_size
       ) do
    window_size = prev_window_size + (new_window_size - old_window_size)

    Logger.debug(fn ->
      "window_size: #{prev_window_size} + (#{new_window_size} - #{old_window_size}) = #{
        window_size
      }"
    end)

    {:ok, %{protocol | window_size: window_size}}
  end

  defp adjust_streams_window_size(
         %{streams: streams} = protocol,
         old_window_size,
         new_window_size
       ) do
    streams =
      Enum.reduce(streams, streams, fn {id, stream}, streams ->
        stream = HTTP2Stream.adjust_window_size(stream, old_window_size, new_window_size)
        Map.put(streams, id, stream)
      end)

    {:ok, %{protocol | streams: streams}}
  end
end
