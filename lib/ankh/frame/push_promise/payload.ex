defmodule Ankh.Frame.PushPromise.Payload do
  @moduledoc """
  PUSH_PROMISE frame payload
  """

  @type t :: %__MODULE__{pad_length: Integer.t, promised_stream_id: Integer.t,
  hbf: binary}
  defstruct [pad_length: 0, promised_stream_id: 0, hbf: <<>>]
end

defimpl Ankh.Frame.Payload, for: Ankh.Frame.PushPromise.Payload do
  import Ankh.Frame.Utils

  def encode!(%{pad_length: pl, promised_stream_id: psi, hbf: hbf},
  flags: %{padded: true}) do
    [<<pl::8, 0::1, psi::31>>, hbf, padding(pl)]
  end

  def encode!(%{promised_stream_id: psi, hbf: hbf}, flags: %{padded: false}) do
    [<<0::1, psi::31>>, hbf]
  end

  def decode!(struct, <<pl::8, _::1, psi::31, data::binary>>,
  flags: %{padded: true}) do
    hbf = binary_part(data, 0, byte_size(data) - pl)
    %{struct | pad_length: pl, promised_stream_id: psi, hbf: hbf}
  end

  def decode!(struct, <<_::8, _::1, psi::31, hbf::binary>>,
  flags: %{padded: false}) do
    %{struct | promised_stream_id: psi, hbf: hbf}
  end
end
