defmodule Ankh.HTTP.Response do
  @moduledoc """
  Ankh HTTP Response
  """

  alias Ankh.HTTP

  @type t() :: %__MODULE__{
          status: HTTP.status(),
          scheme: HTTP.scheme(),
          host: HTTP.host(),
          path: HTTP.path(),
          headers: list(HTTP.header()),
          trailers: list(HTTP.header())
        }
  defstruct status: "200",
            scheme: nil,
            host: nil,
            path: nil,
            method: nil,
            body: [],
            headers: [],
            trailers: []

  @spec put_header(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_header(%{headers: headers} = response, header, value),
    do: %{response | headers: [{String.downcase(header), value} | headers]}

  @spec put_trailer(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_trailer(%{trailers: trailers} = response, trailer, value),
    do: %{response | trailers: [{String.downcase(trailer), value} | trailers]}

  @spec set_status(t(), String.t()) :: t()
  def set_status(response, status), do: %{response | status: status}

  @spec set_method(t(), HTTP.method()) :: t()
  def set_method(response, method), do: %{response | method: method}

  @spec set_scheme(t(), String.t()) :: t()
  def set_scheme(response, scheme), do: %{response | scheme: scheme}

  @spec set_host(t(), String.t()) :: t()
  def set_host(response, host), do: %{response | host: host}

  @spec set_body(t(), iodata) :: t()
  def set_body(response, body), do: %{response | body: body}

  @spec set_path(t(), HTTP.path()) :: t()
  def set_path(response, path), do: %{response | path: path}
end
