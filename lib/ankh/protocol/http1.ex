defmodule Ankh.Protocol.HTTP1 do
  @moduledoc "HTTP/1 protocol implementation"

  alias Ankh.{Protocol, Transport}
  alias Plug.Conn.Status

  @opaque t :: %__MODULE__{
            mode: :client | :server,
            reference: reference(),
            state: :status | :headers | :body | :trailers,
            transport: Transport.t(),
            uri: URI.t()
          }

  defstruct mode: nil, reference: nil, transport: nil, uri: nil, state: :status

  defimpl Protocol do
    alias Ankh.HTTP
    alias HTTP.{Request, Response}

    @crlf "\r\n"

    def accept(%@for{} = protocol, uri, transport, socket, options) do
      with {:ok, transport} <- Transport.new(transport, socket),
           {:ok, transport} <- Transport.accept(transport, options),
           do: {:ok, %{protocol | mode: :server, transport: transport, uri: uri}}
    end

    def connect(%@for{} = protocol, uri, transport, _options),
      do: {:ok, %{protocol | mode: :client, transport: transport, uri: uri}}

    def error(_protocol), do: :ok

    def request(%@for{transport: transport, uri: %URI{host: host}} = protocol, request) do
      %Request{
        method: method,
        path: path,
        headers: headers,
        body: body,
        trailers: trailers
      } = HTTP.put_header(request, "host", host)

      with :ok <-
             Transport.send(transport, [Atom.to_string(method), " ", path, " HTTP/1.1", @crlf]),
           :ok <- send_headers(transport, headers),
           :ok <- send_body(transport, body),
           :ok <- send_headers(transport, trailers) do
        reference = make_ref()
        {:ok, %{protocol | reference: reference}, reference}
      end
    end

    def respond(%@for{transport: transport} = protocol, _request_reference, %Response{
          status: status,
          headers: headers,
          body: body,
          trailers: trailers
        }) do
      reason = Status.reason_phrase(status)
      status = Integer.to_string(status)

      with :ok <- Transport.send(transport, ["HTTP/1.1 ", status, " ", reason, @crlf]),
           :ok <- send_headers(transport, headers),
           :ok <- send_body(transport, body),
           :ok <- send_headers(transport, trailers) do
        {:ok, %{protocol | reference: make_ref()}}
      end
    end

    def stream(protocol, data) do
      data
      |> String.split(@crlf)
      |> process_lines(protocol, [])
    end

    defp send_headers(transport, headers) do
      headers = Enum.map(headers, fn {name, value} -> [name, ": ", value, @crlf] end)

      Transport.send(transport, [@crlf | headers])
    end

    defp send_body(transport, body), do: Transport.send(transport, [body, @crlf])

    defp process_lines([], protocol, responses), do: {:ok, protocol, Enum.reverse(responses)}

    defp process_lines(
           ["HTTP/1.1 " <> status | rest],
           %@for{mode: :client, state: :status} = protocol,
           responses
         ) do
      case String.split(status, " ", parts: 2) do
        [status, _string] ->
          process_headers(
            rest,
            %{protocol | state: :headers},
            [{":status", status}],
            responses
          )

        _ ->
          {:error, :protocol_error}
      end
    end

    defp process_lines(
           [request | rest],
           %@for{mode: :server, state: :status, uri: %URI{scheme: scheme}} = protocol,
           responses
         ) do
      case String.split(request, " ", parts: 3) do
        [method, path, "HTTP/1.1"] ->
          process_headers(
            rest,
            %{protocol | state: :headers},
            [
              {":method", method},
              {":path", path},
              {":scheme", scheme}
            ],
            responses
          )

        _ ->
          {:error, :protocol_error}
      end
    end

    defp process_lines(_lines, _protocol, _responses), do: {:error, :protocol_error}

    defp process_headers(
           [] = lines,
           %@for{reference: reference, state: :trailers} = protocol,
           trailers,
           responses
         ) do
      trailers = Enum.reverse(trailers)

      with :ok <- HTTP.validate_trailers(trailers, false) do
        process_lines(lines, protocol, [{:headers, reference, trailers, true} | responses])
      end
    end

    defp process_headers(
           ["" | rest],
           %@for{reference: reference, state: :headers, mode: :server} = protocol,
           headers,
           responses
         ) do
      headers = Enum.reverse(headers)

      with :ok <- Request.validate_headers(headers, false) do
        process_body(rest, %{protocol | state: :body}, [], [
          {:headers, reference, headers, false} | responses
        ])
      end
    end

    defp process_headers(
           ["" | rest],
           %@for{reference: reference, state: :headers, mode: :client} = protocol,
           headers,
           responses
         ) do
      headers = Enum.reverse(headers)

      with :ok <- Response.validate_headers(headers, false),
           do:
             process_body(rest, %{protocol | state: :body}, [], [
               {:headers, reference, headers, false} | responses
             ])
    end

    defp process_headers(
           [header | rest],
           %@for{state: state} = protocol,
           headers,
           responses
         )
         when state in [:headers, :trailers] do
      case String.split(header, ":", parts: 2) do
        [name, value] ->
          {name, value} =
            case String.downcase(name) do
              "host" ->
                {":authority", value}

              _ ->
                {name, value}
            end

          process_headers(rest, protocol, [{name, String.trim(value)} | headers], responses)

        _line ->
          {:error, :protocol_error}
      end
    end

    defp process_body(
           [] = lines,
           %@for{reference: reference} = protocol,
           [_ | body],
           responses
         ) do
      process_lines(lines, protocol, [
        {:data, reference, Enum.reverse(body), true} | responses
      ])
    end

    defp process_body(
           ["" | rest],
           %@for{reference: reference, state: :body} = protocol,
           [_ | body],
           responses
         ) do
      process_headers(rest, %{protocol | state: :trailers}, [], [
        {:data, reference, Enum.reverse(body), false} | responses
      ])
    end

    defp process_body(
           [data | rest],
           %@for{state: :body} = protocol,
           body,
           responses
         ) do
      process_body(rest, protocol, [@crlf, data | body], responses)
    end
  end
end
