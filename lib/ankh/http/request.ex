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

  @spec validate_headers(HTTP.headers(), boolean(), [HTTP.header_name()]) ::
          :ok | {:error, :protocol_error}
  def validate_headers(headers, strict, forbidden \\ []),
    do: do_validate_headers(headers, strict, forbidden, %{}, false)

  defp do_validate_headers(
         [],
         _strict,
         _forbidden,
         %{method: true, scheme: true, authority: true, path: true},
         _end_pseudo
       ),
       do: :ok

  defp do_validate_headers([], _strict, _forbidden, _stats, _end_pseudo),
    do: {:error, :protocol_error}

  defp do_validate_headers(
         [{":" <> pseudo_header, value} | rest],
         strict,
         forbidden,
         stats,
         false
       )
       when pseudo_header in ["authority", "method", "path", "scheme"] do
    pseudo = String.to_existing_atom(pseudo_header)

    if value == "" or Map.get(stats, pseudo, false) do
      {:error, :protocol_error}
    else
      stats = Map.put(stats, pseudo, true)
      do_validate_headers(rest, strict, forbidden, stats, false)
    end
  end

  defp do_validate_headers(
         [{":" <> _pseaudo_header, _value} | _rest],
         _strict,
         _forbidden,
         _stats,
         _end_pseudo
       ),
       do: {:error, :protocol_error}

  defp do_validate_headers([{header, value} | rest], strict, forbidden, stats, _end_pseudo) do
    case {String.downcase(header), value} do
      {"te", value} when value != "trailers" ->
        {:error, :protocol_error}

      {name, _value} ->
        if name not in forbidden and HTTP.header_name_valid?(header, strict) do
          do_validate_headers(rest, strict, forbidden, stats, true)
        else
          {:error, :protocol_error}
        end
    end
  end
end
