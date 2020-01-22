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
          headers: [HTTP.header()],
          trailers: [HTTP.header()],
          body: HTTP.body(),
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

  @spec put_header(%__MODULE__{}, HTTP.header_name(), HTTP.header_value()) :: %__MODULE__{}
  def put_header(%__MODULE__{headers: headers} = request, header, value),
    do: %__MODULE__{request | headers: [{String.downcase(header), value} | headers]}

  @spec put_trailer(%__MODULE__{}, HTTP.header_name(), HTTP.header_value()) :: %__MODULE__{}
  def put_trailer(%__MODULE__{trailers: trailers} = request, trailer, value),
    do: %__MODULE__{request | trailers: [{String.downcase(trailer), value} | trailers]}

  @spec put_option(%__MODULE__{}, atom, any()) :: %__MODULE__{}
  def put_option(%__MODULE__{options: options} = request, option, value),
    do: %__MODULE__{request | options: [{option, value} | options]}

  @spec set_scheme(%__MODULE__{}, String.t()) :: %__MODULE__{}
  def set_scheme(%__MODULE__{} = request, scheme), do: %__MODULE__{request | scheme: scheme}

  @spec set_host(%__MODULE__{}, String.t()) :: %__MODULE__{}
  def set_host(%__MODULE__{} = request, host), do: %__MODULE__{request | host: host}

  @spec set_body(%__MODULE__{}, iodata) :: %__MODULE__{}
  def set_body(%__MODULE__{} = request, body), do: %__MODULE__{request | body: body}

  @spec set_method(%__MODULE__{}, HTTP.method()) :: %__MODULE__{}
  def set_method(%__MODULE__{} = request, method), do: %__MODULE__{request | method: method}

  @spec set_path(%__MODULE__{}, HTTP.path()) :: %__MODULE__{}
  def set_path(%__MODULE__{} = request, path), do: %__MODULE__{request | path: path}

  @spec set_headers(%__MODULE__{}, [HTTP.header()]) :: %__MODULE__{}
  def set_headers(%__MODULE__{} = request, headers), do: %__MODULE__{request | headers: headers}
end
