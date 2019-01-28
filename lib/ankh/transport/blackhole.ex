defmodule Ankh.Transport.Blackhole do
  @moduledoc """
  NoOp transport module
  """
  alias Ankh.Transport

  @behaviour Transport

  @impl Transport
  def connect(_uri, _receiver, _options \\ []), do: {:ok, __MODULE__}

  @impl Transport
  def accept(_t, _receiver, _options \\ []), do: {:ok, __MODULE__}

  @impl Transport
  def send(_t, _data), do: :ok

  @impl Transport
  def recv(_t, size), do: {:ok, :binary.copy(<<0>>, size)}

  @impl Transport
  def close(_r), do: :ok

  @impl Transport
  def handle_msg(_msg), do: {:data, ""}
end
