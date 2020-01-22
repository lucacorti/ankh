defmodule Ankh.HTTP2 do
  @moduledoc """
  HTTP/2 implementation
  """

  import Ankh.HTTP2.Stream, only: [is_local_stream: 2]
  require Logger

  alias Ankh.{Protocol, Transport}
  alias Ankh.HTTP.{Request, Response}
  alias Ankh.HTTP2.Frame
  alias Frame.{Data, GoAway, Headers, Ping, Priority, Settings, Splittable, WindowUpdate}
  alias HPack.Table
  alias Transport.TLS

  @behaviour Protocol

  @initial_window_size 65_535
  @max_window_size 2_147_483_647
  @max_stream_id 2_147_483_647
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  @tls_options versions: [:"tlsv1.2"],
               ciphers: ["ECDHE-ECDSA-AES128-SHA256", "ECDHE-ECDSA-AES128-SHA"],
               alpn_advertised_protocols: ["h2"]

  @recv_settings [
    header_table_size: 4_096,
    enable_push: true,
    max_concurrent_streams: 128,
    initial_window_size: @max_window_size,
    max_frame_size: 16_384,
    max_header_list_size: 128,
    open_streams: 0
  ]

  @opaque t :: %__MODULE__{}
  defstruct buffer: <<>>,
            header_table_size: 4_096,
            last_stream_id: nil,
            last_local_stream_id: nil,
            last_remote_stream_id: nil,
            recv_hbf_type: nil,
            recv_hpack: nil,
            recv_settings: [],
            send_hpack: nil,
            send_settings: [],
            socket: nil,
            streams: %{},
            transport: TLS,
            uri: nil,
            window_size: @initial_window_size

  @impl Protocol
  def new(options) do
    with {:ok, send_hpack} <- Table.start_link(4_096),
         recv_settings <- Keyword.get(options, :recv_settings, @recv_settings),
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
        with {:ok, protocol} <- send_settings(%{protocol | socket: socket}, @recv_settings),
             {:ok, socket} <- TLS.accept(socket, options) do
          {
            :ok,
            %{
              protocol
              | socket: socket,
                last_local_stream_id: 2,
                last_remote_stream_id: 1,
                last_stream_id: 2,
                uri: uri
            }
          }
        end

      _ ->
        {:error, :protocol_error}
    end
  end

  @impl Protocol
  def close(%{transport: transport, socket: socket}) do
    with :ok <- transport.close(socket) do
      :ok
    end
  end

  @impl Protocol
  def connect(%{recv_settings: recv_settings, transport: transport} = protocol, uri, options) do
    options = Keyword.merge(options, @tls_options)

    protocol = %{
      protocol
      | last_local_stream_id: 1,
        last_remote_stream_id: 2,
        last_stream_id: 1,
        uri: uri
    }

    with {:ok, socket} <- transport.connect(uri, options),
         :ok <- transport.send(socket, @preface),
         {:ok, protocol} <-
           send_frame(%{protocol | socket: socket}, %Settings{
             payload: %Settings.Payload{settings: recv_settings}
           }) do
      {:ok, protocol}
    end
  end

  @impl Protocol
  def stream(%{buffer: buffer, transport: transport} = protocol, msg) do
    with {:ok, data} <- transport.handle_msg(msg),
         {:ok, protocol, responses} <-
           (buffer <> data)
           |> Frame.stream()
           |> Enum.reduce_while({:ok, %{protocol | buffer: buffer <> data}, []}, fn
             {rest, nil}, {:ok, protocol, responses} ->
               {:halt, {:ok, %{protocol | buffer: rest}, responses}}

             {rest, {length, type, id, data}},
             {:ok, %{recv_hbf_type: recv_hbf_type} = protocol, responses} ->
               with {:ok, type} <- Frame.Registry.frame_for_type(protocol, type),
                    {:ok, frame} <- Frame.decode(struct(type), data),
                    :ok <- Logger.debug(fn -> "RECVD #{inspect(frame)}" end),
                    {:ok, protocol, response} <- recv_frame(frame, protocol) do
                 case response do
                   {:data, data, end_stream} ->
                     {:ok, protocol} = process_recv_data(protocol, length, id)

                     {:cont,
                      {:ok, %{protocol | buffer: rest},
                       [{:data, id, data, end_stream} | responses]}}

                   {:error, error} ->
                     {:cont,
                      {:ok, %{protocol | buffer: rest}, [{:error, id, error, true} | responses]}}

                   {type, hbf, end_stream} when type in [:headers, :push_promise] ->
                     case process_recv_headers(protocol, hbf) do
                       {:ok, headers} ->
                         {:cont,
                          {:ok, %{protocol | buffer: rest},
                           [{type, id, headers, end_stream} | responses]}}

                       error ->
                         {:halt, error}
                     end

                   _ ->
                     {:cont, {:ok, %{protocol | buffer: rest}, responses}}
                 end
               else
                 {:error, :not_found} when is_nil(recv_hbf_type) ->
                   {:cont, {:ok, %{protocol | buffer: rest}, responses}}

                 {:error, _reason} = error ->
                   {:halt, error}
               end
           end) do
      {:ok, protocol, Enum.reverse(responses)}
    end
  end

  @impl Protocol
  def request(
        %{uri: %{authority: authority, host: host, path: path, scheme: scheme}} = protocol,
        %{method: method} = request
      ) do
    request =
      request
      |> Request.set_scheme(scheme)
      |> Request.set_host(host)
      |> Request.set_path(path)
      |> Request.set_scheme(scheme)
      |> Request.put_header(":method", method)
      |> Request.put_header(":authority", authority)
      |> Request.put_header(":scheme", scheme)
      |> Request.put_header(":path", path || "/")
      |> IO.inspect

    with {:ok, protocol, %{id: id} = stream} <- get_stream(protocol, nil),
         {:ok, protocol} <- send_headers(protocol, stream, request),
         {:ok, protocol} <- send_data(protocol, stream, request),
         {:ok, protocol} <- send_trailers(protocol, stream, request) do
      {:ok, protocol, id}
    end
  end

  @impl Protocol
  def respond(
        %{uri: %{host: host, scheme: scheme}} = protocol,
        stream_id,
        %{status: status} = response
      ) do
    response =
      response
      |> Response.set_scheme(scheme)
      |> Response.set_host(host)
      |> Response.put_header(":status", status)

    with {:ok, protocol, stream} <- get_stream(protocol, stream_id),
         {:ok, protocol} <- send_headers(protocol, stream, response),
         {:ok, protocol} <- send_data(protocol, stream, response),
         {:ok, protocol} <- send_trailers(protocol, stream, response) do
      {:ok, protocol, stream_id}
    end
  end

  defp get_stream(%{send_settings: send_settings} = protocol, 0) do
    max_frame_size = Keyword.get(send_settings, :max_frame_size, 16_384)
    {:ok, protocol, __MODULE__.Stream.new(0, max_frame_size)}
  end

  defp get_stream(%{last_stream_id: last_stream_id}, id)
       when (not is_nil(id) and id >= @max_stream_id) or last_stream_id >= @max_stream_id do
    {:error, :stream_limit_reached}
  end

  defp get_stream(
         %{
           last_local_stream_id: llid,
           send_settings: send_settings,
           streams: streams
         } = protocol,
         nil = _id
       ) do
    max_frame_size = Keyword.get(send_settings, :max_frame_size, 16_384)
    stream = __MODULE__.Stream.new(llid, max_frame_size)

    {:ok, %{protocol | last_local_stream_id: llid + 2, streams: Map.put(streams, llid, stream)},
     stream}
  end

  defp get_stream(
         %{
           send_settings: send_settings,
           streams: streams,
           last_local_stream_id: llid
         } = protocol,
         id
       ) do
    max_frame_size = Keyword.get(send_settings, :max_frame_size, 16_384)

    case Map.get(streams, id) do
      stream when not is_nil(stream) ->
        {:ok, protocol, stream}

      nil when not is_local_stream(llid, id) ->
        stream = __MODULE__.Stream.new(id, max_frame_size)
        {:ok, %{protocol | streams: Map.put(streams, id, stream)}, stream}

      _ ->
        {:error, :protocol_error}
    end
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
    with {:ok, _length, _type, data} <- Frame.encode(frame),
         :ok <- transport.send(socket, data) do
      Logger.debug(fn -> "SENT #{inspect(frame)}" end)
      {:ok, protocol}
    end
  end

  defp do_send_frame(
         %{socket: socket, streams: streams, transport: transport} = protocol,
         %{stream_id: stream_id} = frame
       ) do
    with {:ok, protocol, %{max_frame_size: max_frame_size} = stream} <-
           get_stream(protocol, stream_id),
         {:ok, stream} <- __MODULE__.Stream.send(stream, frame) do
      frame
      |> Splittable.split(max_frame_size)
      |> Enum.reduce_while({:ok, protocol}, fn frame, _ ->
        with {:ok, length, _type, data} <- Frame.encode(frame),
             :ok <- transport.send(socket, data) do
          Logger.debug(fn -> "SENT #{inspect(%{frame | length: length})}" end)

          {:cont, {:ok, %{protocol | streams: Map.put(streams, stream_id, stream)}}}
        else
          error ->
            {:halt, error}
        end
      end)
    end
  end

  defp recv_frame(
         %{stream_id: 0} = frame,
         %{last_local_stream_id: llid} = protocol
       ) do
    with {:ok, protocol} <- process_connection_frame(frame, protocol) do
      {:ok, protocol, nil}
    else
      {:error, :not_found} ->
        {:ok, protocol, nil}

      {:error, reason} ->
        send_error(protocol, llid - 2, reason)
        {:error, reason}
    end
  end

  defp recv_frame(
         %{stream_id: id} = frame,
         %{last_local_stream_id: llid} = protocol
       )
       when is_local_stream(llid, id) do
    with {:ok, %{streams: streams} = protocol, stream} when not is_nil(stream) <-
           get_stream(protocol, id),
         {:ok, %{recv_hbf_type: recv_hbf_type} = stream, response} <-
           __MODULE__.Stream.recv(stream, frame) do
      {
        :ok,
        %{
          protocol
          | last_local_stream_id: max(llid, id),
            recv_hbf_type: recv_hbf_type,
            streams: Map.put(streams, id, stream)
        },
        response
      }
    else
      {:error, :not_found} ->
        send_error(protocol, llid - 2, :protocol_error)
        {:error, :protocol_error}

      {:error, reason} ->
        send_error(protocol, llid - 2, reason)
        {:error, reason}
    end
  end

  defp recv_frame(
         %{stream_id: id} = frame,
         %{
           last_local_stream_id: llid,
           last_remote_stream_id: lrid,
           streams: streams
         } = protocol
       ) do
    is_priority = Priority.type() == frame.type()

    with {:ok, protocol, stream} when is_priority or id >= lrid <-
           get_stream(protocol, id),
         {:ok, %{recv_hbf_type: recv_hbf_type} = stream, response} <-
           __MODULE__.Stream.recv(stream, frame) do
      lrid = if is_priority, do: lrid, else: id

      {
        :ok,
        %{
          protocol
          | last_remote_stream_id: lrid,
            recv_hbf_type: recv_hbf_type,
            streams: Map.put(streams, id, stream)
        },
        response
      }
    else
      {:error, reason} ->
        send_error(protocol, llid - 2, reason)
        {:error, reason}

      _stream ->
        send_error(protocol, llid - 2, :protocol_error)
        {:error, :protocol_error}
    end
  end

  defp process_connection_frame(
         %Settings{flags: %{ack: false} = flags, payload: %{settings: settings}} = frame,
         %{send_hpack: send_hpack} = protocol
       ) do
    settings_ack = %Settings{
      frame
      | flags: %{flags | ack: true},
        payload: nil,
        length: 0
    }

    case send_frame(protocol, settings_ack) do
      {:ok, protocol} ->
        header_table_size = Keyword.get(settings, :header_table_size)
        window_size = Keyword.get(settings, :initial_window_size)
        Table.resize(header_table_size, send_hpack)

        {
          :ok,
          %{
            protocol
            | header_table_size: header_table_size,
              send_settings: settings,
              window_size: window_size
          }
        }

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

  defp process_connection_frame(%Ping{length: 8, flags: %{ack: false} = flags} = frame, protocol) do
    send_frame(protocol, %Ping{frame | flags: %{flags | ack: true}})
  end

  defp process_connection_frame(%Ping{length: length}, _protocol) when length != 8 do
    {:error, :frame_size_error}
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
         %{
           last_stream_id: last_stream_id,
           protocol: protocol,
           window_size: window_size
         } = protocol
       )
       when window_size + increment > @max_window_size do
    reason = :flow_control_error

    frame = %GoAway{
      payload: %GoAway.Payload{
        last_stream_id: last_stream_id - 2,
        error_code: reason
      }
    }

    send_frame(protocol, frame)

    {:error, reason}
  end

  defp process_connection_frame(
         %WindowUpdate{payload: %{increment: increment}},
         %{window_size: window_size} = protocol
       ) do
    {:ok, %{protocol | window_size: window_size + increment}}
  end

  defp process_connection_frame(%GoAway{payload: %{error_code: code}}, _protocol) do
    {:error, code}
  end

  defp process_connection_frame(_frame, _protocol) do
    {:error, :protocol_error}
  end

  defp send_settings(
         %{
           header_table_size: header_table_size,
           recv_settings: recv_settings,
           send_hpack: send_hpack,
           send_settings: [],
           window_size: window_size
         } = protocol,
         settings
       ) do
    with header_table_size <- Keyword.get(settings, :header_table_size, header_table_size),
         window_size <- Keyword.get(settings, :window_size, window_size),
         enable_push <- Keyword.get(settings, :enable_push, true),
         :ok <- Table.resize(header_table_size, send_hpack),
         recv_settings <- %Settings.Payload{
           settings: Keyword.put(recv_settings, :enable_push, enable_push)
         },
         {:ok, protocol} <- send_frame(protocol, %Settings{payload: recv_settings}) do
      {:ok, %{protocol | window_size: window_size, send_settings: settings}}
    else
      _ ->
        {:error, :compression_error}
    end
  end

  defp send_error(protocol, last_stream_id, error) do
    send_frame(protocol, %GoAway{
      payload: %GoAway.Payload{
        last_stream_id: last_stream_id,
        error_code: error
      }
    })
  end

  defp process_recv_data(protocol, length, stream_id) when length > 0 do
    window_update = %WindowUpdate{payload: %WindowUpdate.Payload{increment: length}}

    with {:ok, protocol} <- send_frame(protocol, window_update),
         {:ok, protocol, %{id: id, state: state}} when state not in [:closed] <-
           get_stream(protocol, stream_id) do
      send_frame(protocol, %{window_update | stream_id: id})
    else
      {:ok, protocol, %{state: :closed}} ->
        {:ok, protocol}

      error ->
        error
    end
  end

  defp process_recv_data(protocol, _length, _stream_id), do: {:ok, protocol}

  defp process_recv_headers(_protocol, [<<>>]), do: {:ok, []}

  defp process_recv_headers(%{recv_hpack: recv_hpack}, hbf) do
    headers =
      hbf
      |> Enum.reverse()
      |> Enum.join()
      |> HPack.decode(recv_hpack)

    if Enum.any?(headers, fn
         :none -> true
         {":path", ""} -> true
         _ -> false
       end) do
      {:error, :compression_error}
    else
      {:ok, headers}
    end
  rescue
    _ ->
      {:error, :compression_error}
  end

  defp send_data(protocol, _stream, %{body: nil}), do: {:ok, protocol}

  defp send_data(protocol, %{id: stream_id}, %{body: body, trailers: trailers}) do
    send_frame(protocol, %Data{
      stream_id: stream_id,
      flags: %Data.Flags{end_stream: Enum.empty?(trailers)},
      payload: %Data.Payload{data: body}
    })
  end

  defp send_headers(protocol, %{id: stream_id}, %{
         headers: headers,
         body: body,
         trailers: trailers
       }) do
    send_frame(protocol, %Headers{
      stream_id: stream_id,
      flags: %Headers.Flags{end_stream: body == nil && List.first(trailers) == nil},
      payload: %Headers.Payload{hbf: headers}
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
end
