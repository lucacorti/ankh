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
          headers: [HTTP.header()],
          trailers: [HTTP.header()]
        }
  defstruct status: "200",
            scheme: nil,
            host: nil,
            path: nil,
            method: nil,
            body: [],
            headers: [],
            trailers: []

  @spec put_header(%__MODULE__{}, HTTP.header_name(), HTTP.header_value()) :: %__MODULE__{}
  def put_header(%__MODULE__{headers: headers} = response, header, value),
    do: %__MODULE__{response | headers: [{String.downcase(header), value} | headers]}

  @spec put_trailer(%__MODULE__{}, HTTP.header_name(), HTTP.header_value()) :: %__MODULE__{}
  def put_trailer(%__MODULE__{trailers: trailers} = response, trailer, value),
    do: %__MODULE__{response | trailers: [{String.downcase(trailer), value} | trailers]}

  @spec set_status(%__MODULE__{}, String.t()) :: %__MODULE__{}
  def set_status(%__MODULE__{} = response, status),
    do: %__MODULE__{response | status: status}

  @spec set_method(%__MODULE__{}, HTTP.method()) :: %__MODULE__{}
  def set_method(%__MODULE__{} = response, method),
    do: %__MODULE__{response | method: method}

  @spec set_scheme(%__MODULE__{}, String.t()) :: %__MODULE__{}
  def set_scheme(%__MODULE__{} = response, scheme),
    do: %__MODULE__{response | scheme: scheme}

  @spec set_host(%__MODULE__{}, String.t()) :: %__MODULE__{}
  def set_host(%__MODULE__{} = response, host),
    do: %__MODULE__{response | host: host}

  @spec set_body(%__MODULE__{}, iodata) :: %__MODULE__{}
  def set_body(%__MODULE__{} = response, body),
    do: %__MODULE__{response | body: body}

  @spec set_path(%__MODULE__{}, HTTP.path()) :: %__MODULE__{}
  def set_path(%__MODULE__{} = response, path),
    do: %__MODULE__{response | path: path}
end
