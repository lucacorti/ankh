defmodule Ankh.HTTP2.Frame.Headers.Payload do
  @moduledoc false

  @type t :: %__MODULE__{
          pad_length: integer,
          exclusive: boolean,
          stream_dependency: integer,
          weight: integer,
          hbf: binary
        }
  defstruct pad_length: 0, exclusive: false, stream_dependency: 0, weight: 0, hbf: []
end

defimpl Ankh.HTTP2.Frame.Encodable, for: Ankh.HTTP2.Frame.Headers.Payload do
  def decode(
        payload,
        <<pl::8, 1::1, sd::31, wh::8, data::binary>>,
        flags: %{padded: true, priority: true}
      ) do
    {:ok,
     %{
       payload
       | pad_length: pl,
         exclusive: true,
         weight: wh,
         stream_dependency: sd,
         hbf: binary_part(data, 0, byte_size(data) - pl)
     }}
  end

  def decode(
        payload,
        <<pl::8, 0::1, sd::31, wh::8, data::binary>>,
        flags: %{padded: true, priority: true}
      ) do
    {:ok,
     %{
       payload
       | pad_length: pl,
         exclusive: false,
         weight: wh,
         stream_dependency: sd,
         hbf: binary_part(data, 0, byte_size(data) - pl)
     }}
  end

  def decode(payload, <<pl::8, data::binary>>, flags: %{padded: true, priority: false}) do
    {:ok, %{payload | pad_length: pl, hbf: binary_part(data, 0, byte_size(data) - pl)}}
  end

  def decode(
        payload,
        <<1::1, sd::31, wh::8, hbf::binary>>,
        flags: %{padded: false, priority: true}
      ) do
    {:ok, %{payload | exclusive: true, weight: wh, stream_dependency: sd, hbf: hbf}}
  end

  def decode(
        payload,
        <<0::1, sd::31, wh::8, hbf::binary>>,
        flags: %{padded: false, priority: true}
      ) do
    {:ok, %{payload | exclusive: false, weight: wh, stream_dependency: sd, hbf: hbf}}
  end

  def decode(payload, <<hbf::binary>>, flags: %{padded: false, priority: false}) do
    {:ok, %{payload | hbf: hbf}}
  end

  def decode(_payload, _data, _options), do: {:error, :decode_error}

  def encode(
        %{pad_length: pad_length, exclusive: true, stream_dependency: sd, weight: wh, hbf: hbf},
        flags: %{padded: true, priority: true}
      ) do
    {:ok, [<<pad_length::8, 1::1, sd::31, wh::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
  end

  def encode(
        %{pad_length: pad_length, exclusive: false, stream_dependency: sd, weight: wh, hbf: hbf},
        flags: %{padded: true, priority: true}
      ) do
    {:ok, [<<pad_length::8, 0::1, sd::31, wh::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
  end

  def encode(%{pad_length: pad_length, hbf: hbf}, flags: %{padded: true, priority: false}) do
    {:ok, [<<pad_length::8>>, hbf, :binary.copy(<<0>>, pad_length)]}
  end

  def encode(
        %{exclusive: true, stream_dependency: sd, weight: wh, hbf: hbf},
        flags: %{padded: false, priority: true}
      ) do
    {:ok, [<<1::1, sd::31, wh::8>>, hbf]}
  end

  def encode(
        %{exclusive: false, stream_dependency: sd, weight: wh, hbf: hbf},
        flags: %{padded: false, priority: true}
      ) do
    {:ok, [<<0::1, sd::31, wh::8>>, hbf]}
  end

  def encode(%{hbf: hbf}, flags: %{padded: false, priority: false}) do
    {:ok, [hbf]}
  end

  def encode(_payload, _options), do: {:error, :encode_error}
end
