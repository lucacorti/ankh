defmodule Ankh.Frame.Error do
  defstruct [code: :no_error]

  def format(:no_error), do: "Graceful shutdown"
  def format(:protocol_error), do: "Protocol error detected"
  def format(:internal_error), do: "Implementation fault"
  def format(:flow_control_error), do: "Flow-control limits exceeded"
  def format(:settings_timeout), do: "Settings not acknowledged"
  def format(:stream_closed), do: "Frame received for closed stream"
  def format(:frame_size_error), do: "Frame size incorrect"
  def format(:refused_stream), do: "Stream not processed"
  def format(:cancel), do: "Stream cancelled"
  def format(:compression_error), do: "Compression state not updated"
  def format(:connect_error), do: "TCP connection error for CONNECT method"
  def format(:enache_your_calm), do: "Processing capacity exceeded"
  def format(:inadequate_security), do: "Negotiated TLS parameters not acceptable"
  def format(:http_1_1_required), do: "Use HTTP/1.1 for the request"
end

defimpl Ankh.Frame.Encoder, for: Ankh.Frame.Error do
  alias Ankh.Frame.Error

  @no_error            0x0
  @protocol_error      0x1
  @internal_error      0x2
  @flow_control_error  0x3
  @settings_timeout    0x4
  @stream_closed       0x5
  @frame_size_error    0x6
  @refused_stream      0x7
  @cancel              0x8
  @compression_error   0x9
  @connect_error       0xa
  @enache_your_calm    0xb
  @inadequate_security 0xc
  @http_1_1_required   0xd

  def decode!(struct, @no_error, _), do: %{struct | code: :no_error}
  def decode!(struct, @protocol_error, _), do: %{struct | code: :protocol_error}
  def decode!(struct, @internal_error, _), do: %{struct | code: :internal_error}
  def decode!(struct, @flow_control_error, _), do: %{struct | code: :flow_control_error}
  def decode!(struct, @settings_timeout, _), do: %{struct | code: :settings_timeout}
  def decode!(struct, @stream_closed, _), do: %{struct | code: :stream_closed}
  def decode!(struct, @frame_size_error, _), do: %{struct | code: :frame_size_error}
  def decode!(struct, @refused_stream, _), do: %{struct | code: :refused_stream}
  def decode!(struct, @cancel, _), do: %{struct | code: :cancel}
  def decode!(struct, @compression_error, _), do: %{struct | code: :compression_error}
  def decode!(struct, @connect_error, _), do: %{struct | code: :connect_error}
  def decode!(struct, @enache_your_calm, _), do: %{struct | code: :enache_your_calm}
  def decode!(struct, @inadequate_security, _), do: %{struct | code: :inadequate_security}
  def decode!(struct, @http_1_1_required, _), do: %{struct | code: :http_1_1_required}

  def encode!(%Error{code: :no_error}, _), do: <<@no_error::32>>
  def encode!(%Error{code: :protocol_error}, _), do: <<@protocol_error::32>>
  def encode!(%Error{code: :internal_error}, _), do: <<@internal_error::32>>
  def encode!(%Error{code: :flow_control_error}, _) do
    <<@flow_control_error::32>>
  end
  def encode!(%Error{code: :settings_timeout}, _) do
    <<@settings_timeout::32>>
  end
  def encode!(%Error{code: :stream_closed}, _), do: <<@stream_closed::32>>
  def encode!(%Error{code: :frame_size_error}, _) do
    <<@frame_size_error::32>>
  end
  def encode!(%Error{code: :refused_stream}, _), do: <<@refused_stream::32>>
  def encode!(%Error{code: :cancel}, _), do: <<@cancel::32>>
  def encode!(%Error{code: :compression_error}, _) do
    <<@compression_error::32>>
  end
  def encode!(%Error{code: :connect_error}, _), do: <<@connect_error::32>>
  def encode!(%Error{code: :enache_your_calm}, _) do
    <<@enache_your_calm::32>>
  end
  def encode!(%Error{code: :inadequate_security}, _) do
    <<@inadequate_security::32>>
  end
  def encode!(%Error{code: :http_1_1_required}, _) do
    <<@http_1_1_required::32>>
  end
end
