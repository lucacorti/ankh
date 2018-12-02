defmodule Ankh.Frame.Headers.Payload do
  @moduledoc false

  @type t :: %__MODULE__{
          pad_length: integer,
          exclusive: boolean,
          stream_dependency: integer,
          weight: integer,
          hbf: binary
        }
  defstruct pad_length: 0, exclusive: false, stream_dependency: 0, weight: 0, hbf: <<>>
end

defimpl Ankh.Frame.Encodable, for: Ankh.Frame.Headers.Payload do
  import Ankh.Frame.Utils

  def encode!(
        %{pad_length: pad_length, exclusive: ex, stream_dependency: sd, weight: wh, hbf: hbf},
        flags: %{padded: true, priority: true}
      ) do
    [<<pad_length::8, bool_to_int!(ex)::1, sd::31, wh::8>>, hbf, :binary.copy(<<0>>, pad_length)]
  end

  def encode!(%{pad_length: pad_length, hbf: hbf}, flags: %{padded: true, priority: false}) do
    [<<pad_length::8>>, hbf, :binary.copy(<<0>>, pad_length)]
  end

  def encode!(
        %{exclusive: ex, stream_dependency: sd, weight: wh, hbf: hbf},
        flags: %{padded: false, priority: true}
      ) do
    [<<bool_to_int!(ex)::1>>, <<sd::31>>, <<wh::8>>, hbf]
  end

  def encode!(%{hbf: hbf}, flags: %{padded: false, priority: false}) do
    [hbf]
  end

  def decode!(
        payload,
        <<pl::8, ex::1, sd::31, wh::8, data::binary>>,
        flags: %{padded: true, priority: true}
      ) do
    hbf = binary_part(data, 0, byte_size(data) - pl)

    %{
      payload
      | pad_length: pl,
        exclusive: int_to_bool!(ex),
        weight: wh,
        stream_dependency: sd,
        hbf: hbf
    }
  end

  def decode!(payload, <<pl::8, data::binary>>, flags: %{padded: true, priority: false}) do
    hbf = binary_part(data, 0, byte_size(data) - pl)
    %{payload | pad_length: pl, hbf: hbf}
  end

  def decode!(
        payload,
        <<ex::1, sd::31, wh::8, hbf::binary>>,
        flags: %{padded: false, priority: true}
      ) do
    %{payload | exclusive: int_to_bool!(ex), weight: wh, stream_dependency: sd, hbf: hbf}
  end

  def decode!(payload, <<hbf::binary>>, flags: %{padded: false, priority: false}) do
    %{payload | hbf: hbf}
  end
end
