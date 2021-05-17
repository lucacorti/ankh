defmodule Ankh.HTTP2.Error do
  @moduledoc """
  HTTP/2 Error encoding and decoding
  """

  @typedoc "HTTP/2 Error"
  @type t ::
          :no_error
          | :protocol_error
          | :internal_error
          | :flow_control_error
          | :settings_timeout
          | :stream_closed
          | :frame_size_error
          | :refused_stream
          | :cancel
          | :compression_error
          | :connect_error
          | :enache_your_calm
          | :inadequate_security
          | :http_1_1_required

  @typedoc "HTTP/2 Error Code"
  @type code :: non_neg_integer()

  @no_error 0x0
  @protocol_error 0x1
  @internal_error 0x2
  @flow_control_error 0x3
  @settings_timeout 0x4
  @stream_closed 0x5
  @frame_size_error 0x6
  @refused_stream 0x7
  @cancel 0x8
  @compression_error 0x9
  @connect_error 0xA
  @enache_your_calm 0xB
  @inadequate_security 0xC
  @http_1_1_required 0xD

  @doc """
  Returns a human readable string for the corresponding error code atom
  """
  @spec format(t()) :: String.t()
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

  @spec decode(code()) :: t()
  def decode(@no_error), do: :no_error
  def decode(@protocol_error), do: :protocol_error
  def decode(@internal_error), do: :internal_error
  def decode(@flow_control_error), do: :flow_control_error
  def decode(@settings_timeout), do: :settings_timeout
  def decode(@stream_closed), do: :stream_closed
  def decode(@frame_size_error), do: :frame_size_error
  def decode(@refused_stream), do: :refused_stream
  def decode(@cancel), do: :cancel
  def decode(@compression_error), do: :compression_error
  def decode(@connect_error), do: :connect_error
  def decode(@enache_your_calm), do: :enache_your_calm
  def decode(@inadequate_security), do: :inadequate_security
  def decode(@http_1_1_required), do: :http_1_1_required
  def decode(_), do: :protocol_error

  @spec encode(t()) :: binary()
  def encode(:no_error), do: <<@no_error::32>>
  def encode(:protocol_error), do: <<@protocol_error::32>>
  def encode(:internal_error), do: <<@internal_error::32>>
  def encode(:flow_control_error), do: <<@flow_control_error::32>>
  def encode(:settings_timeout), do: <<@settings_timeout::32>>
  def encode(:stream_closed), do: <<@stream_closed::32>>
  def encode(:frame_size_error), do: <<@frame_size_error::32>>
  def encode(:refused_stream), do: <<@refused_stream::32>>
  def encode(:cancel), do: <<@cancel::32>>
  def encode(:compression_error), do: <<@compression_error::32>>
  def encode(:connect_error), do: <<@connect_error::32>>
  def encode(:enache_your_calm), do: <<@enache_your_calm::32>>
  def encode(:inadequate_security), do: <<@inadequate_security::32>>
  def encode(:http_1_1_required), do: <<@http_1_1_required::32>>
  def encode(_), do: <<@protocol_error::32>>
end
