defmodule Ankh.HTTP.Request do
  @moduledoc """
  Ankh HTTP Request
  """
  alias Ankh.HTTP

  @type t() :: %__MODULE__{
          host: HTTP.host(),
          scheme: HTTP.scheme(),
          method: HTTP.method(),
          path: HTTP.path(),
          headers: list(HTTP.header()),
          trailers: list(HTTP.header()),
          body: HTTP.body() | nil,
          options: keyword()
        }
  defstruct host: nil,
            scheme: nil,
            method: "GET",
            path: "/",
            headers: [],
            trailers: [],
            body: nil,
            options: []

  @spec new(keyword) :: t()
  def new(attrs \\ []), do: struct(__MODULE__, attrs)

  @spec put_header(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_header(%{headers: headers} = request, header, value),
    do: %{request | headers: [{header, value} | headers]}

  @spec put_trailer(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_trailer(%{trailers: trailers} = request, trailer, value),
    do: %{request | trailers: [{trailer, value} | trailers]}

  @spec put_option(t(), atom, any()) :: t()
  def put_option(%{options: options} = request, option, value),
    do: %{request | options: [{option, value} | options]}

  @spec set_scheme(t(), String.t()) :: t()
  def set_scheme(request, scheme), do: %{request | scheme: scheme}

  @spec set_host(t(), String.t()) :: t()
  def set_host(request, host), do: %{request | host: host}

  @spec set_body(t(), iodata) :: t()
  def set_body(request, body), do: %{request | body: body}

  @spec set_method(t(), HTTP.method()) :: t()
  def set_method(request, method), do: %{request | method: method}

  @spec set_path(t(), HTTP.path()) :: t()
  def set_path(request, path), do: %{request | path: path}

  @spec set_headers(t(), [HTTP.header()]) :: t()
  def set_headers(request, headers), do: %{request | headers: headers}

  @spec set_trailers(t(), [HTTP.header()]) :: t()
  def set_trailers(request, trailers), do: %{request | trailers: trailers}
end
