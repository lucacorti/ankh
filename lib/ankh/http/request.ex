defmodule Ankh.HTTP.Request do
  @moduledoc """
  Ankh HTTP Request
  """
  alias Ankh.HTTP
  alias Plug.Conn.Query

  @typedoc "HTTP request options"
  @type options :: keyword()

  @typedoc "Request method"
  @type method :: :CONNECT | :DELETE | :GET | :HEAD | :OPTIONS | :PATCH | :POST | :PUT | :TRACE

  @typedoc "Request path"
  @type path :: String.t()

  @typedoc "Request query"
  @type query() :: Enum.t()

  @typedoc "HTTP Request"
  @type t() :: %__MODULE__{
          method: method(),
          path: path(),
          headers: HTTP.headers(),
          trailers: HTTP.headers(),
          body: HTTP.body(),
          options: options()
        }

  defstruct method: :GET,
            path: "/",
            headers: [],
            trailers: [],
            body: [],
            options: []

  @spec new(Enum.t()) :: t()
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
    |> set_query(Query.decode(query))
  end

  @spec put_options(t(), options()) :: t()
  def put_options(%{options: options} = request, new_options),
    do: %{request | options: Keyword.merge(options, new_options)}

  @spec set_body(t(), iodata()) :: t()
  def set_body(request, body), do: %{request | body: body}

  @spec set_method(t(), method()) :: t()
  def set_method(request, method), do: %{request | method: method}

  @spec set_path(t(), path()) :: t()
  def set_path(request, path), do: %{request | path: path}

  @spec put_path(t(), path()) :: t()
  def put_path(request, path) do
    new_path =
      case to_uri(request) do
        %URI{query: nil} -> path
        %URI{query: query} -> path <> "?" <> query
      end

    %{request | path: new_path}
  end

  @spec set_query(t(), query()) :: t()
  def set_query(request, query) do
    %URI{path: path} = to_uri(request)

    new_path =
      case query do
        nil ->
          path

        query ->
          query = Query.encode(query)
          path <> "?" <> query
      end

    %{request | path: new_path}
  end

  @spec put_query(t(), query()) :: t()
  def put_query(request, query) do
    query =
      case to_uri(request) do
        %URI{query: nil} ->
          query

        %URI{query: old_query} ->
          old_query
          |> Query.decode()
          |> Map.merge(query)
      end

    set_query(request, query)
  end

  @spec fetch_header_values(t(), HTTP.header_name()) :: [HTTP.header_value()]
  defdelegate fetch_header_values(request, header), to: HTTP

  @spec fetch_trailer_values(t(), HTTP.header_name()) :: [HTTP.header_value()]
  defdelegate fetch_trailer_values(request, trailer), to: HTTP

  @spec put_header(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  defdelegate put_header(request, name, value), to: HTTP

  @spec put_headers(t(), HTTP.headers()) :: t()
  defdelegate put_headers(request, headers), to: HTTP

  @spec put_trailer(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  defdelegate put_trailer(request, name, value), to: HTTP

  @spec put_trailers(t(), HTTP.headers()) :: t()
  defdelegate put_trailers(request, trailers), to: HTTP

  @spec validate_body(t()) :: {:ok, t()} | :error
  defdelegate validate_body(request), to: HTTP
end
