defmodule Ankh.HTTP.Response do
  @moduledoc """
  Ankh HTTP Response
  """

  alias Ankh.HTTP

  @typedoc "Response status"
  @type status :: non_neg_integer()

  @type t() :: %__MODULE__{
          status: status(),
          body: HTTP.body(),
          headers: HTTP.headers(),
          trailers: HTTP.headers(),
          body_fetched: boolean(),
          complete: boolean()
        }
  defstruct status: 200,
            body: [],
            headers: [],
            trailers: [],
            body_fetched: false,
            complete: false

  @spec new(keyword) :: t()
  def new(attrs \\ []), do: struct(__MODULE__, attrs)

  @spec put_header(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_header(%{headers: headers} = response, name, value),
    do: %{response | headers: [{String.downcase(name), value} | headers]}

  @spec put_headers(t(), HTTP.headers()) :: t()
  def put_headers(response, headers),
    do:
      Enum.reduce(headers, response, fn {header, value}, acc -> put_header(acc, header, value) end)

  @spec put_trailer(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_trailer(%{trailers: trailers} = response, name, value),
    do: %{response | trailers: [{String.downcase(name), value} | trailers]}

  @spec put_trailers(t(), HTTP.headers()) :: t()
  def put_trailers(response, trailers) do
    Enum.reduce(trailers, response, fn {header, value}, acc ->
      put_trailer(acc, header, value)
    end)
  end

  @spec set_status(t(), status()) :: t()
  def set_status(response, status), do: %{response | status: status}

  @spec set_body(t(), iodata()) :: t()
  def set_body(response, body), do: %{response | body: body}

  @spec fetch_header_values(t(), HTTP.header_name()) :: [HTTP.header_value()]
  def fetch_header_values(%{headers: headers}, name), do: fetch_values(headers, name)

  @spec fetch_trailer_values(t(), HTTP.header_name()) :: [HTTP.header_value()]
  def fetch_trailer_values(%{trailers: trailers}, name), do: fetch_values(trailers, name)

  defp fetch_values(headers, name) do
    headers
    |> Enum.reduce([], fn
      {^name, value}, acc ->
        [value | acc]

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  @spec fetch_body(t()) :: t()
  def fetch_body(%__MODULE__{body_fetched: false, body: body} = response) do
    body =
      body
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    %{response | body_fetched: true, body: body}
  end

  def fetch_body(%__MODULE__{body_fetched: true} = response), do: response

  @spec validate_body(t()) :: {:ok, t()} | :error
  def validate_body(%{body: body} = request) do
    with content_length when not is_nil(content_length) <-
           request
           |> fetch_header_values("content-length")
           |> List.first(),
         data_length when data_length != content_length <-
           body
           |> IO.iodata_length()
           |> Integer.to_string() do
      :error
    else
      _ ->
        {:ok, request}
    end
  end
end
