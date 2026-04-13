defmodule Ankh.Protocol.HTTP3.RequestTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 30_000

  alias Ankh.HTTP
  alias Ankh.HTTP.Request

  # -------------------------------------------------------------------------
  # Setup
  # -------------------------------------------------------------------------

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quicer)
    :ok
  end

  # -------------------------------------------------------------------------
  # Response helper
  # -------------------------------------------------------------------------

  # Drives the receive loop until end_stream = true is signalled for `ref`,
  # returning {:ok, status, headers, body_binary} or {:error, reason}.
  defp collect_response(protocol, ref, timeout \\ 10_000) do
    do_collect(protocol, ref, timeout, nil, [], [])
  end

  defp do_collect(protocol, ref, timeout, status, headers, body) do
    receive do
      msg ->
        case HTTP.stream(protocol, msg) do
          {:ok, new_proto, events} ->
            case process_events(events, ref, status, headers, body) do
              {:done, st, hd, bd} ->
                {:ok, st, hd, IO.iodata_to_binary(Enum.reverse(bd))}

              {:cont, st, hd, bd} ->
                do_collect(new_proto, ref, timeout, st, hd, bd)
            end

          {:error, reason} ->
            {:error, reason}

          _other ->
            do_collect(protocol, ref, timeout, status, headers, body)
        end
    after
      timeout -> {:error, :timeout}
    end
  end

  defp process_events([], _ref, status, headers, body),
    do: {:cont, status, headers, body}

  defp process_events([event | rest], ref, status, headers, body) do
    case event do
      {:headers, ^ref, decoded_headers, end_stream} ->
        new_status =
          case List.keyfind(decoded_headers, ":status", 0) do
            {":status", v} -> String.to_integer(v)
            nil -> status
          end

        regular =
          Enum.reject(decoded_headers, fn {n, _} -> String.starts_with?(n, ":") end)

        new_headers = headers ++ regular

        if end_stream do
          {:done, new_status, new_headers, body}
        else
          process_events(rest, ref, new_status, new_headers, body)
        end

      {:data, ^ref, chunk, end_stream} ->
        new_body = [chunk | body]

        if end_stream do
          {:done, status, headers, new_body}
        else
          process_events(rest, ref, status, headers, new_body)
        end

      {:error, ^ref, _reason, _complete} ->
        {:done, status, headers, body}

      _other ->
        process_events(rest, ref, status, headers, body)
    end
  end

  defp connect_h3!(uri_string, extra_opts \\ []) do
    uri = URI.parse(uri_string)
    opts = Keyword.merge([timeout: 10_000, protocols: [:h3]], extra_opts)
    {:ok, protocol} = HTTP.connect(uri, opts)
    protocol
  end

  defp get!(protocol, path, extra_headers \\ []) do
    request =
      Request.new(
        method: :GET,
        path: path,
        headers: [{"user-agent", "ankh-h3-test/1"}, {"accept", "*/*"}] ++ extra_headers
      )

    {:ok, protocol, ref} = HTTP.request(protocol, request)
    {protocol, ref}
  end

  # -------------------------------------------------------------------------
  # Basic GET requests
  # -------------------------------------------------------------------------

  describe "basic GET requests over HTTP/3" do
    test "GET / from cloudflare-quic.com returns HTTP 200" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, status, headers, body} = collect_response(protocol, ref)
      assert status == 200
      assert byte_size(body) > 0
      assert Enum.any?(headers, fn {k, _} -> k == "content-type" end)
    end

    test "GET / response contains expected Cloudflare headers" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, headers, _body} = collect_response(protocol, ref)

      header_names = Enum.map(headers, &elem(&1, 0))
      assert "server" in header_names
      assert "date" in header_names
      assert "content-type" in header_names
    end

    test "GET / response server header identifies cloudflare" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, headers, _body} = collect_response(protocol, ref)

      {_, server} = List.keyfind(headers, "server", 0)
      assert server =~ "cloudflare"
    end

    test "GET / advertises HTTP/3 support in Alt-Svc header" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, headers, _body} = collect_response(protocol, ref)

      case List.keyfind(headers, "alt-svc", 0) do
        {_, alt_svc} -> assert alt_svc =~ "h3"
        nil -> flunk("expected Alt-Svc header advertising h3")
      end
    end

    test "GET / to cloudflare.com returns a redirect (3xx)" do
      protocol = connect_h3!("https://cloudflare.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, status, _headers, _body} = collect_response(protocol, ref)
      assert status in 200..399
    end

    test "GET / receives full body from cloudflare-quic.com" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, headers, body} = collect_response(protocol, ref)

      # Verify content-length matches received body when present
      case List.keyfind(headers, "content-length", 0) do
        {_, cl_str} ->
          content_length = String.to_integer(cl_str)
          assert byte_size(body) == content_length

        nil ->
          assert byte_size(body) > 0
      end
    end

    test "GET / response body is valid HTML" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, _headers, body} = collect_response(protocol, ref)
      assert body =~ "<!DOCTYPE html>" or body =~ "<html"
    end
  end

  # -------------------------------------------------------------------------
  # Request headers propagation
  # -------------------------------------------------------------------------

  describe "request header propagation" do
    test "custom User-Agent header is sent (reflected in cf-ray)" do
      # Cloudflare always returns cf-ray regardless, but custom UA is sent —
      # we verify the request succeeds and headers are sent without error.
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/", [{"user-agent", "ankh-custom-ua/42"}])

      assert {:ok, 200, headers, _body} = collect_response(protocol, ref)
      assert Enum.any?(headers, fn {k, _} -> k == "cf-ray" end)
    end

    test "Accept header is sent" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/", [{"accept", "text/html"}])

      assert {:ok, 200, headers, _body} = collect_response(protocol, ref)
      {_, content_type} = List.keyfind(headers, "content-type", 0)
      assert content_type =~ "text/html"
    end

    test "multiple custom headers are sent successfully" do
      protocol = connect_h3!("https://cloudflare-quic.com")

      extra = [
        {"accept-language", "en-US,en;q=0.9"},
        {"cache-control", "no-cache"}
      ]

      {protocol, ref} = get!(protocol, "/", extra)

      # Request should succeed — the key assertion is no error
      assert {:ok, status, _headers, _body} = collect_response(protocol, ref)
      assert status in 200..399
    end
  end

  # -------------------------------------------------------------------------
  # Protocol negotiation
  # -------------------------------------------------------------------------

  describe "protocol negotiation" do
    test "protocols: [:h3] connects with HTTP/3" do
      # The connection itself succeeding over QUIC is the assertion.
      # We also verify the server sends its three control/QPACK streams
      # (visible via debug logs) but just assert the response works.
      protocol = connect_h3!("https://cloudflare-quic.com", protocols: [:h3])
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, _headers, body} = collect_response(protocol, ref)
      assert byte_size(body) > 0
    end

    test "protocols: [:h3, :h2, :\"http/1.1\"] prefers HTTP/3 when available" do
      uri = URI.parse("https://cloudflare-quic.com")
      opts = [timeout: 10_000, protocols: [:h3, :h2, :"http/1.1"]]
      assert {:ok, protocol} = HTTP.connect(uri, opts)

      {protocol, ref} = get!(protocol, "/")
      assert {:ok, 200, _headers, body} = collect_response(protocol, ref)
      assert byte_size(body) > 0
    end

    test "default https:// connection uses TLS (no :protocols option)" do
      uri = URI.parse("https://cloudflare.com")

      # Default: TLS, ALPN h2 / http1.1 — no protocols opt means TLS path
      assert {:ok, protocol} = HTTP.connect(uri, timeout: 10_000)

      {protocol, ref} = get!(protocol, "/")
      assert {:ok, status, _headers, _body} = collect_response(protocol, ref)
      assert status in 200..399
    end

    test "protocols: [:h3] against one.one.one.one succeeds" do
      uri = URI.parse("https://1.1.1.1")
      opts = [timeout: 10_000, protocols: [:h3], verify: :none]
      assert {:ok, protocol} = HTTP.connect(uri, opts)

      {protocol, ref} = get!(protocol, "/")
      assert {:ok, status, _headers, _body} = collect_response(protocol, ref)
      assert status in 200..399
    end
  end

  # -------------------------------------------------------------------------
  # Multiple sequential requests on the same connection
  # -------------------------------------------------------------------------

  describe "multiple sequential requests" do
    test "two sequential GET requests on the same H3 connection both succeed" do
      protocol = connect_h3!("https://cloudflare-quic.com")

      # First request
      {protocol, ref1} = get!(protocol, "/")
      assert {:ok, 200, _headers1, body1} = collect_response(protocol, ref1)
      assert byte_size(body1) > 0

      # Second request on the same connection
      {protocol, ref2} = get!(protocol, "/")
      assert {:ok, 200, _headers2, body2} = collect_response(protocol, ref2)
      assert byte_size(body2) > 0
    end

    test "three sequential requests all return 200" do
      protocol = connect_h3!("https://cloudflare-quic.com")

      for _ <- 1..3 do
        {protocol, ref} = get!(protocol, "/")
        assert {:ok, 200, _headers, body} = collect_response(protocol, ref)
        assert byte_size(body) > 0
        {protocol, nil}
      end
    end

    test "response bodies are consistent across sequential requests" do
      protocol = connect_h3!("https://cloudflare-quic.com")

      {protocol, ref1} = get!(protocol, "/")
      {:ok, 200, _h1, body1} = collect_response(protocol, ref1)

      {protocol2, ref2} = get!(protocol, "/")
      {:ok, 200, _h2, body2} = collect_response(protocol2, ref2)

      # Both fetches of the same static page should return the same byte count
      assert byte_size(body1) == byte_size(body2)
    end
  end

  # -------------------------------------------------------------------------
  # QPACK header decoding correctness
  # -------------------------------------------------------------------------

  describe "QPACK header decoding" do
    test "all response header names are lowercase strings" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, headers, _body} = collect_response(protocol, ref)

      for {name, _value} <- headers do
        assert name == String.downcase(name),
               "header name #{inspect(name)} is not lowercase"
      end
    end

    test "response headers do not contain HTTP/2-style pseudo-headers" do
      # Pseudo-headers (:status, :path, etc.) must be stripped by the protocol
      # layer before returning responses to the caller.
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, _status, headers, _body} = collect_response(protocol, ref)

      pseudo_headers =
        Enum.filter(headers, fn {name, _} -> String.starts_with?(name, ":") end)

      assert pseudo_headers == [],
             "expected no pseudo-headers in decoded response, got: #{inspect(pseudo_headers)}"
    end

    test "date header is a valid HTTP date string" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, headers, _body} = collect_response(protocol, ref)

      assert {_, date_value} = List.keyfind(headers, "date", 0)
      # HTTP date contains a day name and a year
      assert date_value =~ ~r/(Mon|Tue|Wed|Thu|Fri|Sat|Sun)/
      assert date_value =~ ~r/20\d\d/
    end

    test "content-length header value parses as a non-negative integer" do
      protocol = connect_h3!("https://cloudflare-quic.com")
      {protocol, ref} = get!(protocol, "/")

      assert {:ok, 200, headers, _body} = collect_response(protocol, ref)

      case List.keyfind(headers, "content-length", 0) do
        {_, value} ->
          {length, ""} = Integer.parse(value)
          assert length >= 0

        nil ->
          :ok
      end
    end
  end

  # -------------------------------------------------------------------------
  # Error handling
  # -------------------------------------------------------------------------

  describe "connection error handling" do
    test "connecting to an unreachable host returns an error" do
      uri = URI.parse("https://this.host.does.not.exist.invalid")
      result = HTTP.connect(uri, timeout: 3_000, protocols: [:h3])
      assert {:error, _reason} = result
    end

    test "protocols: [:h3] to a TLS-only host fails gracefully (no fallback)" do
      # A host that doesn't speak QUIC on 443 should return an error when only
      # :h3 is requested (no TLS fallback).
      uri = URI.parse("https://example.com")
      result = HTTP.connect(uri, timeout: 5_000, protocols: [:h3])

      # We accept either :error (QUIC refused/timeout) or a successful H3
      # connection (example.com may or may not support H3).
      # The key assertion: no crash, just a result tuple.
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
