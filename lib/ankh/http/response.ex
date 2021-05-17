defmodule Ankh.HTTP.Response do
  @moduledoc """
  Ankh HTTP Response
  """

  alias Ankh.HTTP

  @typedoc "Response status"
  @type status :: pos_integer()

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

  @spec new(Enum.t()) :: t()
  def new(attrs \\ []), do: struct(__MODULE__, attrs)

  @spec set_status(t(), status()) :: t()
  def set_status(response, status), do: %{response | status: status}

  @spec set_body(t(), iodata()) :: t()
  def set_body(response, body), do: %{response | body: body}

  @spec fetch_body(t()) :: t()
  def fetch_body(%__MODULE__{body_fetched: false, body: body} = response) do
    fetched_body =
      body
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    %{response | body_fetched: true, body: fetched_body}
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

  @spec validate_headers(HTTP.headers(), boolean(), [HTTP.header_name()]) ::
          :ok | {:error, :protocol_error}
  def validate_headers(headers, strict, forbidden \\ []),
    do: do_validate_headers(headers, strict, forbidden, false, false)

  defp do_validate_headers(
         [],
         _strict,
         _forbidden,
         true = _status,
         _end_pseudo
       ),
       do: :ok

  defp do_validate_headers([], _strict, _forbidden, _status, _end_pseudo),
    do: {:error, :protocol_error}

  defp do_validate_headers(
         [{":status", value} | rest],
         strict,
         forbidden,
         false = _status,
         false
       ) do
    case Integer.parse(value) do
      {status, ""} when status in 100..599 ->
        do_validate_headers(rest, strict, forbidden, true, false)

      _ ->
        {:error, :protocol_error}
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
