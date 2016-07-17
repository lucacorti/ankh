defmodule Http2.Frame.Priority.Payload do
  defstruct [exclusive: false, stream_dependency: 0, weight: 0]
end

defimpl Http2.Frame.Encoder, for: Http2.Frame.Priority.Payload do
  alias Http2.Frame.Priority.Payload

  import Http2.Frame.Encoder.Utils

  def encode!(%Payload{exclusive: ex, stream_dependency: sd, weight: wh}, _) do
    <<bool_to_int(ex)::1, sd::31, wh::8>>
  end

  def decode!(struct, <<ex::1, sd::31, wh::8>>, _) do
    %{struct | exclusive: int_to_bool(ex), stream_dependency: sd, weight: wh}
  end
end
