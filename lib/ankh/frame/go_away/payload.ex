defmodule Ankh.Frame.GoAway.Payload do
  @moduledoc false

  @type t :: %__MODULE__{last_stream_id: integer, error_code: atom, data: binary}
  defstruct last_stream_id: nil, error_code: nil, data: <<>>
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.GoAway.Payload do
  alias Ankh.Error

  def decode!(payload, <<_::1, lsid::31, error::32>>, _) do
    %{payload | last_stream_id: lsid, error_code: Error.decode!(error)}
  end

  def decode!(payload, <<_::1, lsid::31, error::32, data::binary>>, _) do
    %{payload | last_stream_id: lsid, error_code: Error.decode!(error), data: data}
  end

  def encode!(%{last_stream_id: lsid, error_code: error, data: data}, _) do
    [<<0::1, lsid::31>>, Error.encode!(error), data]
  end
end
