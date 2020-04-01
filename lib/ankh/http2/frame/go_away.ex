defmodule Ankh.HTTP2.Frame.GoAway do
  @moduledoc false

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{last_stream_id: integer, error_code: atom, data: binary}
    defstruct last_stream_id: nil, error_code: nil, data: <<>>
  end

  alias __MODULE__.Payload
  use Ankh.HTTP2.Frame, type: 0x7, payload: Payload
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.GoAway.Payload do
  alias Ankh.HTTP2.Error

  def decode(payload, <<_::1, lsid::31, error::32>>, _) do
    {:ok, %{payload | last_stream_id: lsid, error_code: Error.decode(error)}}
  end

  def decode(payload, <<_::1, lsid::31, error::32, data::binary>>, _) do
    {:ok, %{payload | last_stream_id: lsid, error_code: Error.decode(error), data: data}}
  end

  def decode(_payload, _data, _options), do: {:error, :decode_error}

  def encode(%{last_stream_id: lsid, error_code: error, data: data}, _) do
    {:ok, [<<0::1, lsid::31>>, Error.encode(error), data]}
  end

  def encode(_payload, _options), do: {:error, :encode_error}
end
