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

  @spec set_status(t(), status()) :: t()
  def set_status(response, status), do: %{response | status: status}

  @spec set_body(t(), iodata()) :: t()
  def set_body(response, body), do: %{response | body: body}

  @spec fetch_body(t()) :: t()
  def fetch_body(%__MODULE__{body_fetched: false, body: body} = response) do
    body =
      body
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    %{response | body_fetched: true, body: body}
  end

  def fetch_body(%__MODULE__{body_fetched: true} = response), do: response

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
  defdelegate validate_body(response), to: HTTP
end
