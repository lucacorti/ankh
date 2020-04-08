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

  @typedoc "Request method"
  @type method :: :CONNECT | :DELETE | :GET | :HEAD | :OPTIONS | :PATCH | :POST | :PUT | :TRACE

  @typedoc "Request path"
  @type path :: String.t()

  @typedoc "HTTP Request"
  @type t() :: %__MODULE__{
          method: method(),
          path: path(),
          headers: HTTP.headers(),
          trailers: HTTP.headers(),
          body: HTTP.body() | nil,
          options: options()
        }
  defstruct method: :GET,
            path: "/",
            headers: [],
            trailers: [],
            body: [],
            options: []

  @spec new(keyword) :: t()
  def new(attrs \\ []), do: struct(__MODULE__, attrs)

  @spec to_uri(t()) :: URI.t()
  def to_uri(%{path: path}), do: URI.parse(path)

  @spec from_uri(URI.t()) :: t()
  def from_uri(uri), do: put_uri(new(), uri)

  @spec put_uri(t(), URI.t()) :: t()
  def put_uri(request, %URI{path: nil, query: nil}), do: request
  def put_uri(request, %URI{path: path, query: nil}), do: set_path(request, path)
  def put_uri(request, %URI{path: nil, query: query}), do: set_query(request, query)

  def put_uri(request, %URI{path: path, query: query}) do
    request
    |> set_path(path)
    |> set_query(URI.decode_query(query))
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

  @spec set_method(t(), method()) :: t()
  def set_method(request, method), do: %{request | method: method}

  @spec set_path(t(), path()) :: t()
  def set_path(request, path), do: %{request | path: path}

  @spec put_path(t(), path()) :: t()
  def put_path(request, path) do
    %URI{query: query} = to_uri(request)

    new_path =
      case query do
        nil -> path
        query -> path <> "?" <> query
      end

    %{request | path: new_path}
  end

  @spec set_query(t(), Enum.t()) :: t()
  def set_query(request, query) do
    %URI{path: path} = to_uri(request)

    new_path =
      case query do
        nil -> path
        query -> path <> "?" <> URI.encode_query(query)
      end

    %{request | path: new_path}
  end

  @spec put_query(t(), Enum.t()) :: t()
  def put_query(request, query) do
    %URI{query: old_query} = to_uri(request)

    query =
      case old_query do
        nil ->
          query

        old_query ->
          old_query
          |> URI.decode_query()
          |> Map.merge(query)
      end

    set_query(request, query)
  end
end
