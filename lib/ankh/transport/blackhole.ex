defmodule Ankh.Transport.Blackhole do
  @moduledoc """
  NoOp transport module
  """

  @behaviour Ankh.Transport
  def connect(_uri, _receiver, _options \\ []), do: {:ok, __MODULE__}
  def accept(_t, _receiver, _options \\ []), do: {:ok, __MODULE__}
  def send(_t, _data), do: :ok
  def recv(_t, size), do: {:ok, :binary.copy(<<0>>, size)}
  def close(_r), do: :ok
end
