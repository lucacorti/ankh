defmodule Ankh.HTTP2.Error do
  @moduledoc """
  HTTP/2 Error encoding and decoding
  """

  @errors [
    {0x0, :no_error, "Graceful shutdown"},
    {0x1, :protocol_error, "Protocol error detected"},
    {0x2, :internal_error, "Implementation fault"},
    {0x3, :flow_control_error, "Flow-control limits exceeded"},
    {0x4, :settings_timeout, "Settings not acknowledged"},
    {0x5, :stream_closed, "Frame received for closed stream"},
    {0x6, :frame_size_error, "Frame size incorrect"},
    {0x7, :refused_stream, "Stream not processed"},
    {0x8, :cancel, "Stream cancelled"},
    {0x9, :compression_error, "Compression state not updated"},
    {0xA, :connect_error, "TCP connection error for CONNECT method"},
    {0xB, :enanche_your_calm, "Processing capacity exceeded"},
    {0xC, :inadequate_security, "Negotiated TLS parameters not acceptable"},
    {0xD, :http_1_1_required, "Use HTTP/1.1 for the request"}
  ]

  @typedoc "HTTP/2 Error"
  @type t ::
          unquote(
            Enum.map_join(@errors, " | ", &inspect(elem(&1, 1)))
            |> Code.string_to_quoted!()
          )

  @typedoc "HTTP/2 Error Code"
  @type code :: non_neg_integer()

  @doc """
  Returns a human readable string for the corresponding error code atom
  """
  @spec format(t()) :: String.t()
  for {_code, name, message} <- @errors do
    def format(unquote(name)), do: unquote(message)
  end

  def format(_name), do: "Protocol error detected"

  @spec decode(code()) :: t()
  for {code, name, _message} <- @errors do
    def decode(unquote(code)), do: unquote(name)
  end

  def decode(_code), do: :protocol_error

  @spec encode(t()) :: binary()
  for {code, name, _message} <- @errors do
    def encode(unquote(name)), do: <<unquote(code)::32>>
  end

  def encode(_name), do: <<0x1::32>>
end
