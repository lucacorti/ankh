defmodule Ankh.Protocol.HTTP2.Error do
  @moduledoc """
  HTTP/2 Error encoding and decoding
  """
  alias Ankh.HTTP.Error

  errors = [
    {0x0, :no_error},
    {0x1, :protocol_error},
    {0x2, :internal_error},
    {0x3, :flow_control_error},
    {0x4, :settings_timeout},
    {0x5, :stream_closed},
    {0x6, :frame_size_error},
    {0x7, :refused_stream},
    {0x8, :cancel},
    {0x9, :compression_error},
    {0xA, :connect_error},
    {0xB, :enanche_your_calm},
    {0xC, :inadequate_security},
    {0xD, :http_1_1_required}
  ]

  @typedoc "HTTP/2 Error Code"
  @type code :: non_neg_integer()

  def format(_name), do: "Protocol error detected"

  @spec decode(code()) :: Error.reason()
  for {code, reason} <- errors do
    def decode(unquote(code)), do: unquote(reason)
  end

  def decode(_code), do: :protocol_error

  @spec encode(Error.reason()) :: binary()
  for {code, reason} <- errors do
    def encode(unquote(reason)), do: <<unquote(code)::32>>
  end

  def encode(_name), do: <<0x1::32>>
end
