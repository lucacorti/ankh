defmodule Ankh.Transport do
  @moduledoc """
  Transport behavior
  """

  @typedoc "Transport socket"
  @type t :: any()

  @typedoc """
  Transport options

  Valid options are:
    - `transport_opts`: Transport options for the tcp/ssl erlang modules
  """
  @type options :: Keyword.t()

  @doc """
  Accepts a client connection
  """
  @callback accept(t, Keyword.t()) :: {:ok, t} | {:error, any()}

  @doc """
  Closes the connection
  """
  @callback close(t()) :: :ok | {:error, any()}

  @doc """
  Connects to an host
  """
  @callback connect(URI.t(), Keyword.t()) :: {:ok, t()} | {:error, any()}

  @doc """
  Sends data
  """
  @callback send(t(), iodata()) :: :ok | {:error, any()}

  @doc """
  Receives data
  """
  @callback recv(t(), integer) :: {:ok, iodata()} | {:error, any()}

  @doc """
  Handles transport messages
  """
  @callback handle_msg(any()) :: {:ok, iodata()} | {:error, any()}
end
