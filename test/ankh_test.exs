defmodule AnkhTest do
  use ExUnit.Case

  require Logger

  alias Ankh.HTTP
  alias HTTP.Request

  doctest Ankh

  test "Ankh HTTP request" do
    # url = "https://localhost:8000"
    url = "https://www.fantacast.it"
    # url = "https://www.google.com"

    request = Request.new()

    assert {:ok, protocol} =
             url
             |> URI.parse()
             |> HTTP.connect()

    assert {:ok, protocol, reference} = HTTP.request(protocol, request)

    receive_response(protocol, reference)
  end

  defp receive_response(protocol, reference) do
    receive do
      msg ->
        case HTTP.stream(protocol, msg) do
          {:other, msg} ->
            Logger.warn("unknown message: #{inspect(msg)}")

          {:ok, protocol, []} ->
            receive_response(protocol, reference)

          {:ok, protocol, responses} ->
            complete =
              Enum.find(responses, fn
                {_type, ^reference, _data, true = _complete} -> true
                _ -> false
              end)

            unless complete do
              receive_response(protocol, reference)
            end

          error ->
            error
        end
    end
  end
end
