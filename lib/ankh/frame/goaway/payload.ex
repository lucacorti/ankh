defmodule Ankh.Frame.Goaway.Payload do
  @moduledoc """
  GOAWAY frame payload
  """

  @type t :: %__MODULE__{last_stream_id: Integer.t, error_code: atom,
  data: binary}
  defstruct [last_stream_id: nil, error_code: nil, data: nil]
end

defimpl Ankh.Frame.Payload, for: Ankh.Frame.Goaway.Payload do
  alias Ankh.Frame.Error

  def decode!(struct, <<_::1, lsid::31, error::32>>, _) do
    %{struct | last_stream_id: lsid, error_code: Error.decode!(error)}
  end

  def decode!(struct, <<_::1, lsid::31, error::32, data::binary>>, _) do
    %{struct | last_stream_id: lsid, error_code: Error.decode!(error),
      data: data}
  end

  def encode!(%{last_stream_id: lsid, error_code: error, data: data}, _) do
    <<0::1, lsid::31, Error.encode!(error)::32, data>>
  end
end
