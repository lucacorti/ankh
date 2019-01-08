defmodule Ankh.Transport do
  @moduledoc """
  Transport behavior
  """
  alias Ankh.Connection.Receiver

  @typedoc "Transport reference"
  @type t :: term

  @doc """
  Accepts a client connection
  """
  @callback accept(t, Receiver.t(), Keyword.t()) :: {:ok, t} | {:error, term}

  @doc """
  Closes the connection
  """
  @callback close(t) :: :ok | {:error, term}

  @doc """
  Connects to an host
  """
  @callback connect(URI.t(), Receiver.t(), Keyword.t()) :: {:ok, t} | {:error, term}

  @doc """
  Sends data
  """
  @callback send(t, iodata) :: :ok | {:error, term}

  @doc """
  Receives data
  """
  @callback recv(t, integer) :: {:ok, binary} | {:error, term}
end
