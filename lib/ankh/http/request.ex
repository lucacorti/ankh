defmodule Ankh.HTTP.Request do
  @moduledoc """
  Ankh HTTP Request
  """
  alias Ankh.HTTP

  @typedoc """
  HTTP request options

  Available options are
    - `follow_redirects`: If true, when an HTTP redirect is received a new request is made to the redirect URL, else the redirect is returned. Defaults to `true`
    - `max_redirects`: Maximum number of redirects to follow, defaults to `10`
    - `request_timeout`: Timeout for the request, defaults to `20_000` milliseconds
  """
  @type options :: Keyword.t()

  @typedoc "HTTP Request"
  @type t() :: %__MODULE__{
          method: HTTP.method(),
          path: HTTP.path(),
          query: HTTP.query(),
          headers: HTTP.headers(),
          trailers: HTTP.headers(),
          body: HTTP.body() | nil,
          options: options()
        }
  defstruct method: :GET,
            path: "/",
            query: "",
            headers: [],
            trailers: [],
            body: [],
            options: []

  @spec new(keyword) :: t()
  def new(attrs \\ []), do: struct(__MODULE__, attrs)

  @spec to_uri(t()) :: URI.t()
  def to_uri(%{path: path, query: query}) do
    %URI{path: path, query: query}
  end

  @spec put_uri(t(), URI.t()) :: t()
  def put_uri(request, %URI{path: path, query: query}) do
    %{request | path: path || "/", query: query || ""}
  end

  @spec put_header(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_header(%{headers: headers} = request, header, value),
    do: %{request | headers: [{String.downcase(header), value} | headers]}

  @spec put_trailer(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_trailer(%{trailers: trailers} = request, trailer, value),
    do: %{request | trailers: [{String.downcase(trailer), value} | trailers]}

  @spec put_options(t(), options()) :: t()
  def put_options(%{options: options} = request, new_options),
    do: %{request | options: Keyword.merge(options, new_options)}

  @spec set_body(t(), iodata) :: t()
  def set_body(request, body), do: %{request | body: body}

  @spec set_method(t(), HTTP.method()) :: t()
  def set_method(request, method), do: %{request | method: method}

  @spec set_path(t(), HTTP.path()) :: t()
  def set_path(request, path), do: %{request | path: path}

  @spec set_query(t(), HTTP.path()) :: t()
  def set_query(request, query), do: %{request | query: query}
end
