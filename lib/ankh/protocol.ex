defmodule Ankh.Protocol do
  @moduledoc """
  Transport behavior
  """
  alias Ankh.Transport
  alias Ankh.HTTP.{Request, Response}

  @typep t :: any()
  @typep request_reference :: any()


  @doc """
  Creates a new connection context
  """
  @callback new(keyword) :: t()

  @doc """
  Accepts a client connection
  """
  @callback accept(t(), URI.t(), Transport.t(), Transport.options()) ::
              {:ok, t()} | {:error, any()}

  @doc """
  Connects to an host
  """
  @callback connect(t(), URI.t(), Transport.options()) :: {:ok, t()} | {:error, any()}

  @doc """
  Sends a request
  """
  @callback request(t(), Request.t(), keyword) :: {:ok, reference(), t()} | {:error, any()}

  @doc """
  Sends a request
  """
  @callback respond(t(), request_reference, Response.t(), keyword) ::
              {:ok, reference(), t()} | {:error, any()}

  @doc """
  Closes the connection
  """
  @callback close(t()) :: :ok | {:error, any()}

  @doc """
  Handles transport messages
  """
  @callback stream(t(), any()) :: {:ok, binary, t()} | {:other, t()} | {:error, any()}
end
