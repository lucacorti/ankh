defmodule Ankh.HTTP.Response do
  @moduledoc """
  Ankh HTTP Response
  """

  alias Ankh.HTTP

  @type t() :: %__MODULE__{
          status: HTTP.status(),
          path: HTTP.path(),
          body: HTTP.body(),
          headers: HTTP.headers(),
          trailers: HTTP.headers(),
          body_fetched: boolean(),
          complete: boolean()
        }
  defstruct status: 200,
            path: nil,
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

  @spec put_trailer(t(), HTTP.header_name(), HTTP.header_value()) :: t()
  def put_trailer(%{trailers: trailers} = response, name, value),
    do: %{response | trailers: [{String.downcase(name), value} | trailers]}

  @spec set_status(t(), HTTP.status()) :: t()
  def set_status(response, status), do: %{response | status: status}

  @spec set_body(t(), iodata) :: t()
  def set_body(response, body), do: %{response | body: body}

  @spec set_path(t(), HTTP.path()) :: t()
  def set_path(response, path), do: %{response | path: path}

  @spec fetch_body(t()) :: t()
  def fetch_body(%__MODULE__{body_fetched: false, body: body} = response) do
    body =
      body
      |> Enum.reverse()
      |> Enum.join()

    %{response | body_fetched: true, body: body}
  end

  def fetch_body(%__MODULE__{body_fetched: true} = response), do: response
end
