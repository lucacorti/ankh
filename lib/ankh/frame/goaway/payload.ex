defmodule Ankh.Frame.GoAway.Payload do
  defstruct [last_stream_id: nil, error_code: nil, data: nil]
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.GoAway.Payload do
  alias Ankh.Frame.GoAway.Payload
  alias Ankh.Frame.{Encoder, Error}

  def decode!(struct, <<_::1, lsid::31, e::32>>, _) do
    %{struct | last_stream_id: lsid,
      error_code: Encoder.decode!(%Error{}, e, [])}
  end

  def decode!(struct, <<_::1, lsid::31, e::32, data::binary>>, _) do
    %{struct | last_stream_id: lsid,
      error_code: Encoder.decode!(%Error{}, e, []), data: data}
  end

  def encode!(%Payload{last_stream_id: lsid, error_code: error, data: data}, _)
  do
    <<0::1, lsid::31, Encoder.encode!(error, [])::32, data>>
  end
end
